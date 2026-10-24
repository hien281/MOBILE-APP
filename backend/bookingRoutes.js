const express = require('express');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');
const router = express.Router();

const HOURS = Array.from({ length: 16 }, (_, i) => `${String(i + 6).padStart(2, '0')}:00`);
const COURTS = ['court_1', 'court_2', 'court_3'];
const MAX_SLOTS = 100;

function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}
function endTime(start) {
  return `${String(Number(start.slice(0, 2)) + 1).padStart(2, '0')}:00`;
}
function slotId(fieldId, courtId, date, startTime) {
  // Existing legacy booking slot IDs (without court) remain reserved for all courts.
  return `${fieldId}_${courtId}_${date}_${startTime.replace(':', '-')}`;
}
function normalizedSelections(body) {
  // Multi-selection payload: { fieldId, selections: [{date,courtId,startTime}, ...] }
  // Also accept the previous single-slot payload for older clients.
  const items = Array.isArray(body.selections)
    ? body.selections
    : [{ date: body.date, courtId: body.courtId || 'court_1', startTime: body.startTime }];
  if (items.length === 0 || items.length > MAX_SLOTS) return null;
  const seen = new Set();
  const normalized = [];
  for (const item of items) {
    if (!item || !validDate(item.date) || !COURTS.includes(item.courtId) || !HOURS.includes(item.startTime)) return null;
    const key = `${item.date}|${item.courtId}|${item.startTime}`;
    if (seen.has(key)) return null;
    seen.add(key);
    normalized.push({ date: item.date, courtId: item.courtId, startTime: item.startTime });
  }
  return normalized;
}

router.get('/fields/:id/availability', async (req, res) => {
  try {
    const { id } = req.params;
    const { date } = req.query;
    if (!validDate(date)) return res.status(400).json({ success: false, message: 'Ngày không hợp lệ.' });
    const field = await db.collection('fields').doc(id).get();
    if (!field.exists) return res.status(404).json({ success: false, message: 'Không tìm thấy sân.' });
    const snapshot = await db.collection('booking_slots').where('fieldId', '==', id).where('date', '==', date).get();
    const booked = new Set();
    const legacy = new Set();
    for (const doc of snapshot.docs) {
      const item = doc.data();
      if (COURTS.includes(item.courtId)) booked.add(`${item.courtId}|${item.startTime}`);
      else legacy.add(item.startTime); // old reservations must not become bookable again
    }
    const courts = COURTS.map((courtId, i) => ({
      courtId, name: `Sân ${i + 1}`,
      slots: HOURS.map(startTime => ({ startTime, available: !legacy.has(startTime) && !booked.has(`${courtId}|${startTime}`) }))
    }));
    return res.json({ success: true, fieldId: id, date, courts, slots: courts[0].slots });
  } catch (error) {
    console.error('Availability error:', error);
    return res.status(500).json({ success: false, message: 'Không thể kiểm tra lịch trống.' });
  }
});

router.post('/bookings', requireAuth, async (req, res) => {
  try {
    const { fieldId } = req.body || {};
    const selections = normalizedSelections(req.body || {});
    if (typeof fieldId !== 'string' || !fieldId.trim() || !selections) {
      return res.status(400).json({ success: false, message: 'Thông tin đặt sân không hợp lệ (tối đa 100 khung giờ).' });
    }
    // Vietnam venue-local time; date-only validation independent of UTC date.
    const nowVN = new Date(Date.now() + 7 * 60 * 60 * 1000).toISOString().slice(0, 16);
    if (selections.some(s => `${s.date}T${s.startTime}` <= nowVN)) {
      return res.status(400).json({ success: false, message: 'Không thể đặt khung giờ đã qua.' });
    }
    const fieldRef = db.collection('fields').doc(fieldId);
    const bookingRef = db.collection('bookings').doc();
    const refs = selections.map(s => db.collection('booking_slots').doc(slotId(fieldId, s.courtId, s.date, s.startTime)));
    const legacyRefs = selections.map(s => db.collection('booking_slots').doc(`${fieldId}_${s.date}_${s.startTime.replace(':', '-')}`));
    const result = await db.runTransaction(async tx => {
      // All reads MUST precede writes in a Firestore transaction.
      const field = await tx.get(fieldRef);
      const slots = await Promise.all(refs.map(ref => tx.get(ref)));
      const legacySlots = await Promise.all(legacyRefs.map(ref => tx.get(ref)));
      if (!field.exists) return { status: 404, message: 'Không tìm thấy sân.' };
      if (slots.some(s => s.exists) || legacySlots.some(s => s.exists)) {
        return { status: 409, message: 'Có ít nhất một khung giờ đã được đặt. Hãy tải lại lịch.' };
      }
      const price = field.data().price;
      if (typeof price !== 'number' || !Number.isFinite(price) || price < 0) {
        return { status: 500, message: 'Giá sân chưa được cấu hình hợp lệ.' };
      }
      const booking = {
        fieldId, userId: req.user.id, type: selections.length > 1 ? 'multi' : 'single',
        selections: selections.map(s => ({ ...s, endTime: endTime(s.startTime) })),
        totalPrice: price * selections.length, status: 'confirmed', createdAt: new Date().toISOString(),
      };
      // Keep compatibility for old single-booking readers.
      if (selections.length === 1) Object.assign(booking, { ...selections[0], endTime: endTime(selections[0].startTime) });
      tx.create(bookingRef, booking);
      refs.forEach((ref, i) => tx.create(ref, { bookingId: bookingRef.id, fieldId, ...selections[i] }));
      return { success: true, bookingId: bookingRef.id, booking };
    });
    if (result.status) return res.status(result.status).json({ success: false, message: result.message });
    return res.status(201).json(result);
  } catch (error) {
    console.error('Booking error:', error);
    return res.status(500).json({ success: false, message: 'Không thể đặt sân.' });
  }
});

module.exports = router;
