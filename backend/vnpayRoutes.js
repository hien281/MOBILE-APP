const express = require('express');
const crypto = require('crypto');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');

const router = express.Router();
const GATEWAY = process.env.VNPAY_URL || 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html';
const {
  createMembershipCard
} = require('./membershipActivation');

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

    // Khóa phương thức thanh toán bằng Firestore transaction.
    const lockResult = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);

      if (!fresh.exists) {
        return 'not_found';
      }

      const current = fresh.data();

      const currentExpiryMs = current.expiresAt?.toMillis
        ? current.expiresAt.toMillis()
        : new Date(current.expiresAt).getTime();

      if (
        current.userId !== req.user.id ||
        current.status !== 'pending_payment' ||
        current.paymentStatus !== 'pending' ||
        !Number.isFinite(currentExpiryMs) ||
        currentExpiryMs <= Date.now() ||
        current.totalPrice !== amount ||
        (current.paymentMethod && current.paymentMethod !== 'vnpay')
      ) {
        return 'invalid';
      }

      tx.update(ref, {
        paymentMethod: 'vnpay',
        vnpTxnRef: bookingId
      });

      return 'locked';
    });

    if (lockResult !== 'locked') {
      return res.status(409).json({
        success: false,
        message: 'Đơn đặt sân không còn hợp lệ để thanh toán VNPay.'
      });
    }

    return res.json({
      success: true,
      paymentUrl: url,
      bookingId,
      expiresAt: booking.expiresAt
    });
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
    // Xử lý IPN cho đơn hội viên
if (id.startsWith('MEM_')) {
  const orderId = id.slice(4);

  if (!/^[A-Za-z0-9_-]{1,128}$/.test(orderId)) {
    return reply('01', 'Invalid membership order');
  }

  const orderRef = db.collection('membership_orders').doc(orderId);
  const cardRef = db.collection('user_memberships').doc(orderId);

  const result = await db.runTransaction(async tx => {
    const orderDoc = await tx.get(orderRef);
    const cardDoc = await tx.get(cardRef);

    if (!orderDoc.exists) return '01';

    const order = orderDoc.data();

    if (
      order.paymentMethod !== 'vnpay' ||
      order.vnpTxnRef !== id
    ) {
      return '01';
    }

    if (String(order.totalPrice * 100) !== req.query.vnp_Amount) {
      return '04';
    }

    if (
      order.paymentStatus === 'paid' ||
      order.paymentStatus === 'refund_required'
    ) {
      return '02';
    }

    const success =
      req.query.vnp_ResponseCode === '00' &&
      req.query.vnp_TransactionStatus === '00';

    if (!success) return '00';

    const now = new Date();
    const expires = order.expiresAt?.toMillis
      ? order.expiresAt.toMillis()
      : Date.parse(order.expiresAt);

    if (
      order.status !== 'pending_payment' ||
      order.paymentStatus !== 'pending' ||
      !Number.isFinite(expires) ||
      expires <= now.getTime() ||
      cardDoc.exists
    ) {
      tx.update(orderRef, {
        paymentStatus: 'refund_required',
        latePaymentAt: now.toISOString(),
        vnpTransactionNo: String(req.query.vnp_TransactionNo || '')
      });

      return '00';
    }

    const paidAt = now.toISOString();

    tx.update(orderRef, {
      status: 'confirmed',
      paymentStatus: 'paid',
      paymentMethod: 'vnpay',
      paidAt,
      vnpTransactionNo: String(req.query.vnp_TransactionNo || '')
    });

    tx.create(
      cardRef,
      createMembershipCard(order, orderId, paidAt)
    );

    return '00';
  });

  const messages = {
    '00': 'Confirm Success',
    '01': 'Order not found',
    '02': 'Order already confirmed',
    '04': 'Invalid amount'
  };

  return reply(result, messages[result] || 'Unknown');
}
    const bookingRef = db.collection('bookings').doc(id);
    const outcome = await db.runTransaction(async tx => {
      const bookingDoc = await tx.get(bookingRef);
      if (!bookingDoc.exists) return '01';
      const booking = bookingDoc.data();
      if (
        booking.paymentMethod !== 'vnpay' ||
        booking.vnpTxnRef !== id
      ) {
        return '01';
      }
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

// POST /api/payments/vnpay/membership/create
router.post('/payments/vnpay/membership/create', requireAuth, async (req, res) => {
  try {
    const { VNPAY_TMN_CODE, VNPAY_HASH_SECRET, PUBLIC_BASE_URL } = process.env;

    if (!VNPAY_TMN_CODE || !VNPAY_HASH_SECRET || !PUBLIC_BASE_URL) {
      return res.status(503).json({
        success: false,
        message: 'VNPay chưa được cấu hình.'
      });
    }

    const orderId = req.body?.orderId;

    if (
      typeof orderId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(orderId)
    ) {
      return res.status(400).json({
        success: false,
        message: 'Mã đơn hội viên không hợp lệ.'
      });
    }

    const orderRef = db.collection('membership_orders').doc(orderId);

    const order = await db.runTransaction(async tx => {
      const doc = await tx.get(orderRef);

      if (!doc.exists || doc.data().userId !== req.user.id) {
        throw new Error('Không tìm thấy đơn hội viên.');
      }

      const data = doc.data();

      const expires = data.expiresAt?.toMillis
        ? data.expiresAt.toMillis()
        : Date.parse(data.expiresAt);

      if (
        data.status !== 'pending_payment' ||
        data.paymentStatus !== 'pending' ||
        !Number.isFinite(expires) ||
        expires <= Date.now() ||
        (data.paymentMethod && data.paymentMethod !== 'vnpay')
      ) {
        throw new Error('Đơn không còn hiệu lực thanh toán VNPay.');
      }

      if (
        !Number.isSafeInteger(data.totalPrice) ||
        data.totalPrice <= 0 ||
        data.totalPrice * 100 > Number.MAX_SAFE_INTEGER
      ) {
        throw new Error('Số tiền không hợp lệ.');
      }

      tx.update(orderRef, {
        paymentMethod: 'vnpay',
        vnpTxnRef: `MEM_${orderId}`
      });

      return data;
    });

    const expires = order.expiresAt?.toMillis
      ? order.expiresAt.toMillis()
      : Date.parse(order.expiresAt);

    const base = PUBLIC_BASE_URL.replace(/\/$/, '');

    if (!base.startsWith('https://')) {
      return res.status(503).json({
        success: false,
        message: 'PUBLIC_BASE_URL phải dùng HTTPS.'
      });
    }

    const now = new Date();
    const txnRef = `MEM_${orderId}`;

    const params = {
      vnp_Version: '2.1.0',
      vnp_Command: 'pay',
      vnp_TmnCode: VNPAY_TMN_CODE,
      vnp_Amount: String(order.totalPrice * 100),
      vnp_CurrCode: 'VND',
      vnp_TxnRef: txnRef,
      vnp_OrderInfo: `Thanh toan hoi vien SPORTY ${orderId}`,
      vnp_OrderType: 'other',
      vnp_Locale: 'vn',
      vnp_ReturnUrl: `${base}/api/payments/vnpay/return`,
      vnp_IpAddr: (req.ip || '127.0.0.1').replace(/^::ffff:/, ''),
      vnp_CreateDate: vnTime(now),
      vnp_ExpireDate: vnTime(new Date(expires))
    };

    params.vnp_SecureHash = sign(params, VNPAY_HASH_SECRET);

    return res.json({
      success: true,
      paymentUrl: `${GATEWAY}?${new URLSearchParams(params).toString()}`,
      orderId,
      expiresAt: order.expiresAt
    });

  } catch (error) {
    console.error('VNPay membership create error:', error);

    return res.status(409).json({
      success: false,
      message: error.message || 'Không tạo được thanh toán hội viên.'
    });
  }
});

module.exports = router;
