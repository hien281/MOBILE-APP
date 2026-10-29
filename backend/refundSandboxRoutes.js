const express = require('express');
const crypto = require('crypto');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');
const router = express.Router();
const SIM_DELAY_MS = 5000;
const now = () => new Date().toISOString();
const slotId = (fieldId, s) => `${fieldId}_${s.courtId}_${s.date}_${s.startTime.replace(':', '-')}`;
const keyFor = k => k.replace('|', '__');
const validKey = k => typeof k === 'string' && /^\d{4}-\d{2}-\d{2}\|court_[1-9]\d*$/.test(k);
const validId = id => /^[\w-]{1,128}$/.test(id || '');
const err = (code, message) => ({code, message});
function sessions(b) {
  const all = Array.isArray(b.selections) ? b.selections : [];
  const grouped = new Map();
  for (const s of all) {
    const k = `${s.date}|${s.courtId}`;
    if (!grouped.has(k)) grouped.set(k, []);
    grouped.get(k).push(s);
  }
  return grouped;
}
function requestFor(b, sessionKey) {
  return sessionKey ? b.refundSessionRequests?.[keyFor(sessionKey)] : b.refundSandbox;
}
router.post('/bookings/:id/refund-request', requireAuth, async (req, res) => {
  if (!validId(req.params.id)) return res.status(400).json({success:false,message:'Mã đơn không hợp lệ.'});
  const sessionKey = req.body?.sessionKey ?? null;
  if (sessionKey !== null && !validKey(sessionKey)) return res.status(400).json({success:false,message:'Buổi không hợp lệ.'});
  try {
    const ref = db.collection('bookings').doc(req.params.id);
    const result = await db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (!doc.exists || doc.data().userId !== req.user.id) return err(404,'Không tìm thấy đơn.');
      const b = doc.data();
      if (b.bookingType === 'membership' || b.paymentStatus !== 'paid' || !['confirmed','booked'].includes(b.status)) return err(409,'Đơn không đủ điều kiện hoàn tiền.');
      const grouped = sessions(b);
      if (!grouped.size || (sessionKey && !grouped.has(sessionKey))) return err(404,'Không tìm thấy buổi.');
      const selected = sessionKey ? grouped.get(sessionKey) : [...grouped.values()].flat();
      const starts = selected.map(s => Date.parse(`${s.date}T${s.startTime}:00+07:00`));
      if (starts.some(t => !Number.isFinite(t)) || Math.min(...starts) - Date.now() < 86400000) return err(409,'Chỉ được yêu cầu hoàn trước giờ chơi ít nhất 24 tiếng.');
      const existing = requestFor(b, sessionKey);
      if (existing) return {success:true, status:existing.status, amount:existing.amount, simulation:true};
      const all = [...grouped.values()].flat();
      const cancelled = new Set(b.cancelledSessions || []);
      if (sessionKey && cancelled.has(sessionKey)) return err(409,'Buổi đã huỷ.');
      if (!sessionKey && (cancelled.size || Object.keys(b.refundSessionRequests || {}).length)) return err(409,'Đơn đã có yêu cầu hoàn tiền từng buổi.');
      if (sessionKey && b.refundSandbox) return err(409,'Đơn đã có yêu cầu hoàn toàn bộ.');
      const amount = Math.round(Number(b.totalPrice) * selected.length / all.length);
      if (!Number.isSafeInteger(amount) || amount <= 0) return err(409,'Số tiền hoàn không hợp lệ.');
      const request = {status:'processing', amount, requestedAt:now(), approvedAt:now(), simulation:true,
        refundId:`SIM-${crypto.randomUUID()}`, sessionKey};
      if (sessionKey) tx.update(ref,{[`refundSessionRequests.${keyFor(sessionKey)}`]:request});
      else tx.update(ref,{refundSandbox:request,refundRequestStatus:'processing',refundAmount:amount,refundRequestedAt:request.requestedAt});
      return {success:true,status:'processing',amount,simulation:true};
    });
    return res.status(result.code || 200).json(result.code ? {success:false,message:result.message} : result);
  } catch(e) {console.error('Sandbox refund request',e);return res.status(500).json({success:false,message:'Không tạo được yêu cầu hoàn tiền mô phỏng.'});}
});
router.get('/bookings/:id/refund-status', requireAuth, async (req,res) => {
  if (!validId(req.params.id)) return res.status(400).json({success:false,message:'Mã đơn không hợp lệ.'});
  const sessionKey = req.query.sessionKey || null;
  if (sessionKey && !validKey(sessionKey)) return res.status(400).json({success:false,message:'Buổi không hợp lệ.'});
  try {
    const ref = db.collection('bookings').doc(req.params.id);
    const result = await db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (!doc.exists || doc.data().userId !== req.user.id) return err(404,'Không tìm thấy đơn.');
      const b = doc.data();
      const record = requestFor(b,sessionKey);
      if (!record) return {success:true,status:'none',simulation:true};
      if (record.status !== 'processing' || Date.now()-Date.parse(record.requestedAt) < SIM_DELAY_MS)
        return {success:true,...record};
      const grouped = sessions(b);
      const selected = sessionKey ? grouped.get(sessionKey) : [...grouped.values()].flat();
      if (!selected?.length) return err(409,'Không tìm thấy buổi để hoàn.');
      const slotRefs = selected.map(s => db.collection('booking_slots').doc(slotId(b.fieldId,s)));
      const slotDocs = await Promise.all(slotRefs.map(r=>tx.get(r)));
      if (slotDocs.some(d => !d.exists || d.data().bookingId !== doc.id)) {
        const failed = {...record,status:'failed',failedAt:now(),failureReason:'Khung giờ đã thay đổi. Cần kiểm tra thủ công.'};
        if (sessionKey) tx.update(ref,{[`refundSessionRequests.${keyFor(sessionKey)}`]:failed});
        else tx.update(ref,{refundSandbox:failed,refundRequestStatus:'failed'});
        return {success:true,...failed};
      }
      const completed = {...record,status:'succeeded',refundedAt:now()};
      const cancelled = new Set(b.cancelledSessions || []);
      const updates = {};
      if (sessionKey) {
        cancelled.add(sessionKey);
        updates[`refundSessionRequests.${keyFor(sessionKey)}`] = completed;
        updates[`cancelledSessionDetails.${keyFor(sessionKey)}`] = {cancelledAt:completed.refundedAt,refundAmount:completed.amount,refundId:completed.refundId,simulation:true,status:'cancelled'};
      } else {
        for (const k of grouped.keys()) cancelled.add(k);
        updates.refundSandbox = completed;
        updates.refundRequestStatus = 'succeeded';
      }
      updates.cancelledSessions = [...cancelled];
      updates.status = [...grouped.keys()].every(k => cancelled.has(k)) ? 'cancelled' : b.status;
      if (updates.status === 'cancelled') updates.cancelledAt = completed.refundedAt;
      tx.update(ref,updates);
      slotDocs.forEach(d=>tx.delete(d.ref));
      return {success:true,...completed};
    });
    return res.status(result.code || 200).json(result.code ? {success:false,message:result.message} : result);
  } catch(e) {console.error('Sandbox refund status',e);return res.status(500).json({success:false,message:'Không kiểm tra được hoàn tiền mô phỏng.'});}
});
module.exports = router;
