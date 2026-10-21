const express = require('express');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');

const router = express.Router();

// Các khung giờ cố định, mỗi khung 1 tiếng
const TIME_SLOTS = [
  '06:00', '07:00', '08:00', '09:00',
  '10:00', '11:00', '12:00', '13:00',
  '14:00', '15:00', '16:00', '17:00',
  '18:00', '19:00', '20:00', '21:00',
];

// GET /api/fields/:id/availability?date=2026-10-25
router.get('/fields/:id/availability', async (req, res) => {
  try {
    const { id } = req.params;
    const { date } = req.query;

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '')) {
      return res.status(400).json({
        success: false,
        message: 'Ngày không hợp lệ.',
      });
    }

    const fieldDoc = await db.collection('fields').doc(id).get();

    if (!fieldDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Không tìm thấy sân.',
      });
    }

    const snapshot = await db
      .collection('booking_slots')
      .where('fieldId', '==', id)
      .where('date', '==', date)
      .get();

    const bookedTimes = new Set(
      snapshot.docs.map((doc) => doc.data().startTime)
    );

    const slots = TIME_SLOTS.map((time) => ({
      startTime: time,
      available: !bookedTimes.has(time),
    }));

    return res.json({
      success: true,
      fieldId: id,
      date,
      slots,
    });
  } catch (error) {
    console.error('Availability error:', error);
    return res.status(500).json({
      success: false,
      message: 'Không thể kiểm tra lịch trống.',
    });
  }
});

// POST /api/bookings
router.post('/bookings', requireAuth, async (req, res) => {
  try {
    const { fieldId, date, startTime } = req.body;

    if (
      typeof fieldId !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}$/.test(date || '') ||
      !TIME_SLOTS.includes(startTime)
    ) {
      return res.status(400).json({
        success: false,
        message: 'Thông tin đặt sân không hợp lệ.',
      });
    }

    const fieldRef = db.collection('fields').doc(fieldId);
    const bookingRef = db.collection('bookings').doc();

    const slotId =
      `${fieldId}_${date}_${startTime.replace(':', '-')}`;

    const slotRef = db.collection('booking_slots').doc(slotId);

    const result = await db.runTransaction(async (transaction) => {
      const fieldDoc = await transaction.get(fieldRef);
      const slotDoc = await transaction.get(slotRef);

      if (!fieldDoc.exists) {
        return { error: 'Không tìm thấy sân.', status: 404 };
      }

      if (slotDoc.exists) {
        return { error: 'Khung giờ này đã được đặt.', status: 409 };
      }

      const price = fieldDoc.data().price;

      const booking = {
        fieldId,
        userId: req.user.id,
        date,
        startTime,
        endTime: `${String(Number(startTime.slice(0, 2)) + 1).padStart(2, '0')}:00`,
        totalPrice: price,
        status: 'confirmed',
        createdAt: new Date().toISOString(),
      };

      transaction.create(bookingRef, booking);

      transaction.create(slotRef, {
        bookingId: bookingRef.id,
        fieldId,
        date,
        startTime,
      });

      return {
        success: true,
        bookingId: bookingRef.id,
        booking,
      };
    });

    if (result.error) {
      return res.status(result.status).json({
        success: false,
        message: result.error,
      });
    }

    return res.status(201).json(result);
  } catch (error) {
    console.error('Booking error:', error);

    return res.status(500).json({
      success: false,
      message: 'Không thể đặt sân.',
    });
  }
});

module.exports = router;
