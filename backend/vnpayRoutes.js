const express = require('express');
const crypto = require('crypto');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');

const router = express.Router();
const GATEWAY = process.env.VNPAY_URL || 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html';

function sign(params, secret) {
  const sorted = Object.keys(params).sort().map(k =>
    `${encodeURIComponent(k).replace(/%20/g, '+')}=${encodeURIComponent(String(params[k])).replace(/%20/g, '+')}`
  ).join('&');
  return crypto.createHmac('sha512', secret).update(sorted, 'utf8').digest('hex');
}

function vnTime(date) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'
  }).formatToParts(date);
  const v = Object.fromEntries(parts.map(p => [p.type, p.value]));
  return `${v.year}${v.month}${v.day}${v.hour}${v.minute}${v.second}`;
}

function slotId(fieldId, s) {
  return `${fieldId}_${s.courtId}_${s.date}_${s.startTime.replace(':', '-')}`;
}

router.post('/payments/vnpay/create', requireAuth, async (req, res) => {
  try {
    const { VNPAY_TMN_CODE, VNPAY_HASH_SECRET, PUBLIC_BASE_URL } = process.env;
    if (!VNPAY_TMN_CODE || !VNPAY_HASH_SECRET || !PUBLIC_BASE_URL) {
      return res.status(503).json({ success: false, message: 'VNPay chưa được cấu hình trên backend.' });
    }
    const bookingId = req.body?.bookingId;
    if (typeof bookingId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(bookingId)) {
      return res.status(400).json({ success: false, message: 'Mã đặt sân không hợp lệ.' });
    }
    const ref = db.collection('bookings').doc(bookingId);
    const doc = await ref.get();
    if (!doc.exists || doc.data().userId !== req.user.id) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy đơn đặt sân.' });
    }
    const booking = doc.data();
    const expires = Date.parse(booking.expiresAt);
    if (booking.status !== 'pending_payment' || booking.paymentStatus !== 'pending' ||
        !Number.isFinite(expires) || expires <= Date.now()) {
      return res.status(409).json({ success: false, message: 'Đơn không còn hiệu lực thanh toán.' });
    }
    const amount = booking.totalPrice;
    if (!Number.isSafeInteger(amount) || amount <= 0 || amount * 100 > Number.MAX_SAFE_INTEGER) {
      return res.status(400).json({ success: false, message: 'Số tiền đơn không hợp lệ.' });
    }
    const base = PUBLIC_BASE_URL.replace(/\/$/, '');
    if (!/^https:\/\//.test(base)) {
      return res.status(503).json({ success: false, message: 'PUBLIC_BASE_URL phải là HTTPS.' });
    }
    const now = new Date();
    const params = {
      vnp_Version: '2.1.0', vnp_Command: 'pay', vnp_TmnCode: VNPAY_TMN_CODE,
      vnp_Amount: String(amount * 100), vnp_CurrCode: 'VND',
      vnp_TxnRef: bookingId, vnp_OrderInfo: `Thanh toan SPORTY ${bookingId}`,
      vnp_OrderType: 'other', vnp_Locale: 'vn',
      vnp_ReturnUrl: `${base}/api/payments/vnpay/return`,
      vnp_IpAddr: (req.ip || '127.0.0.1').replace(/^::ffff:/, ''),
      vnp_CreateDate: vnTime(now), vnp_ExpireDate: vnTime(new Date(expires))
    };
    params.vnp_SecureHash = sign(params, VNPAY_HASH_SECRET);
    const url = `${GATEWAY}?${new URLSearchParams(params).toString()}`;
    return res.json({ success: true, paymentUrl: url, bookingId, expiresAt: booking.expiresAt });
  } catch (error) {
    console.error('VNPay create error:', error);
    return res.status(500).json({ success: false, message: 'Không tạo được thanh toán VNPay.' });
  }
});

function verify(query) {
  const secret = process.env.VNPAY_HASH_SECRET;
  if (!secret || typeof query.vnp_SecureHash !== 'string') return false;
  const provided = query.vnp_SecureHash.toLowerCase();
  if (!/^[0-9a-f]{128}$/.test(provided)) return false;
  const fields = Object.fromEntries(Object.entries(query).filter(([k, v]) =>
    k.startsWith('vnp_') && k !== 'vnp_SecureHash' && k !== 'vnp_SecureHashType' && typeof v === 'string'
  ));
  const expected = sign(fields, secret);
  return crypto.timingSafeEqual(Buffer.from(provided, 'hex'), Buffer.from(expected, 'hex'));
}

router.get('/payments/vnpay/ipn', async (req, res) => {
  const reply = (code, message) => res.json({ RspCode: code, Message: message });
  try {
    if (!verify(req.query) || req.query.vnp_TmnCode !== process.env.VNPAY_TMN_CODE) {
      return reply('97', 'Invalid signature');
    }
    const id = req.query.vnp_TxnRef;
    if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(id)) return reply('01', 'Invalid order');
    const bookingRef = db.collection('bookings').doc(id);
    const outcome = await db.runTransaction(async tx => {
      const bookingDoc = await tx.get(bookingRef);
      if (!bookingDoc.exists) return '01';
      const booking = bookingDoc.data();
      if (String(booking.totalPrice * 100) !== req.query.vnp_Amount) return '04';
      if (booking.paymentStatus === 'paid') return '02';
      if (booking.paymentStatus === 'refund_required') return '02';
      const success = req.query.vnp_ResponseCode === '00' && req.query.vnp_TransactionStatus === '00';
      if (!success) return '00'; // Failed/abandoned payments never confirm the booking.
      const selections = Array.isArray(booking.selections) ? booking.selections : [];
      if (!selections.length) return '99';
      const refs = selections.map(s => db.collection('booking_slots').doc(slotId(booking.fieldId, s)));
      const slotDocs = await Promise.all(refs.map(ref => tx.get(ref)));
      const valid = booking.status === 'pending_payment' && booking.paymentStatus === 'pending' &&
        Date.parse(booking.expiresAt) > Date.now() &&
        slotDocs.every(doc => doc.exists && doc.data().bookingId === id && doc.data().status === 'held');
      if (!valid) {
        // Payment arrived after cancellation/expiration. Never occupy somebody else's slot.
        tx.update(bookingRef, {
          paymentStatus: 'refund_required',
          latePaymentTransactionNo: String(req.query.vnp_TransactionNo || ''),
          latePaymentAt: new Date().toISOString()
        });
        return '00';
      }
      tx.update(bookingRef, {
        status: 'confirmed', paymentStatus: 'paid', paymentMethod: 'vnpay',
        paidAt: new Date().toISOString(),
        vnpTransactionNo: String(req.query.vnp_TransactionNo || '')
      });
      slotDocs.forEach(doc => tx.update(doc.ref, { status: 'confirmed', expiresAt: null }));
      return '00';
    });
    const messages = { '00': 'Confirm Success', '01': 'Order not found', '02': 'Order already confirmed', '04': 'Invalid amount', '99': 'Unknown error' };
    return reply(outcome, messages[outcome] || 'Unknown');
  } catch (error) {
    console.error('VNPay IPN error:', error);
    return reply('99', 'Unknown error');
  }
});

router.get('/payments/vnpay/return', (req, res) => {
  const valid = verify(req.query) && req.query.vnp_TmnCode === process.env.VNPAY_TMN_CODE;
  res.status(valid ? 200 : 400).type('html').send(
    `<html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font-family:sans-serif;text-align:center;padding:35px"><h2>${valid ? 'Da quay lai tu VNPay' : 'Ket qua khong hop le'}</h2><p>Mo lai SPORTY va bam Kiem tra trang thai don.</p><p>Chi backend xac minh IPN moi co the xac nhan thanh toan.</p></body></html>`
  );
});

module.exports = router;
