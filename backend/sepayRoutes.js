const express = require('express');
const crypto = require('crypto');
const { db } = require('./firebase');

const router = express.Router();
const {
  createMembershipCard
} = require('./membershipActivation');

function slotId(fieldId, s) {
  return `${fieldId}_${s.courtId}_${s.date}_${s.startTime.replace(':', '-')}`;
}

function validSecret(provided, expected) {
  if (typeof provided !== 'string' || !expected) return false;

  const a = Buffer.from(provided);
  const b = Buffer.from(expected);

  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

router.post('/payments/sepay/ipn', async (req, res) => {
  try {
    const secret = process.env.SEPAY_SECRET_KEY;

    const providedSecret = req.get('X-Secret-Key');

    if (!validSecret(providedSecret, secret)) {
      console.warn('SePay IPN authentication failed', {
        hasHeader: typeof providedSecret === 'string',
        hasConfiguredSecret: Boolean(secret),
        headerLength: providedSecret?.length ?? 0,
        configuredLength: secret?.length ?? 0
      });

      return res.status(401).json({ success: false });
    }

    const data = req.body;

    if (
    data?.notification_type !== 'ORDER_PAID' ||
    data?.order?.order_status !== 'CAPTURED' ||
    data?.transaction?.transaction_status !== 'APPROVED' ||
    data?.transaction?.transaction_type !== 'PAYMENT' ||
    data?.transaction?.payment_method !== 'BANK_TRANSFER'
    ) {
    return res.json({ success: true });
    }

    const bookingId = data.order.order_invoice_number;
    const amount = Number(data.order.order_amount);
    if (
    data.transaction.transaction_currency !== 'VND' ||
    Number(data.transaction.transaction_amount) !== amount
    ) {
    return res.status(400).json({
        success: false,
        message: 'Số tiền giao dịch không khớp.'
    });
    }

    if (
      typeof bookingId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(bookingId) ||
      !Number.isSafeInteger(amount) ||
      amount <= 0 ||
      data.order.order_currency !== 'VND'
    ) {
      return res.status(400).json({ success: false });
    }

    // Xử lý hóa đơn hội viên trước khi xử lý booking.
if (bookingId.startsWith('MEM_')) {
  const orderId = bookingId.substring(4);

  if (!/^[A-Za-z0-9_-]{1,128}$/.test(orderId)) {
    return res.status(400).json({
      success: false,
      message: 'Mã đơn hội viên không hợp lệ.'
    });
  }

  const transactionId = data.transaction?.id;

  if (
    transactionId === undefined ||
    transactionId === null ||
    String(transactionId).trim() === ''
  ) {
    return res.status(400).json({
      success: false,
      message: 'Thiếu mã giao dịch.'
    });
  }

  const orderRef = db.collection('membership_orders').doc(orderId);
  const cardRef = db.collection('user_memberships').doc(orderId);

  const result = await db.runTransaction(async tx => {
    // Đọc tất cả tài liệu trước khi ghi.
    const orderDoc = await tx.get(orderRef);
    const cardDoc = await tx.get(cardRef);

    if (!orderDoc.exists) return 'not_found';

    const order = orderDoc.data();

    if (
      order.paymentMethod !== 'sepay' ||
      order.sepayInvoiceNumber !== bookingId
    ) {
      return 'invalid_payment_method';
    }

    if (Number(order.totalPrice) !== amount) {
      return 'invalid_amount';
    }

    if (
      order.paymentStatus === 'paid' ||
      order.paymentStatus === 'refund_required'
    ) {
      return order.sepayTransactionId === String(transactionId)
        ? 'already_processed'
        : 'different_transaction';
    }

    const now = new Date();
    const paidAt = now.toISOString();

    const expiryMs = order.expiresAt?.toMillis
      ? order.expiresAt.toMillis()
      : new Date(order.expiresAt).getTime();

    const valid =
      order.status === 'pending_payment' &&
      order.paymentStatus === 'pending' &&
      Number.isFinite(expiryMs) &&
      expiryMs > now.getTime() &&
      !cardDoc.exists;

    if (!valid) {
      tx.update(orderRef, {
        paymentStatus: 'refund_required',
        latePaymentAt: paidAt,
        sepayTransactionId: String(transactionId)
      });

      return 'late_payment';
    }

    // Xác nhận đơn hội viên đã thanh toán.
    tx.update(orderRef, {
      status: 'confirmed',
      paymentStatus: 'paid',
      paymentMethod: 'sepay',
      paidAt,
      sepayTransactionId: String(transactionId)
    });

    // Mỗi đơn chỉ kích hoạt được một thẻ.
    tx.create(
      cardRef,
      createMembershipCard(order, orderId, paidAt)
    );

    return 'confirmed';
  });

  if ([
    'not_found',
    'invalid_payment_method',
    'invalid_amount',
    'different_transaction'
  ].includes(result)) {
    return res.status(400).json({
      success: false,
      result
    });
  }

  return res.json({
    success: true,
    result
  });
}
    const bookingRef = db.collection('bookings').doc(bookingId);

    const result = await db.runTransaction(async tx => {
      const doc = await tx.get(bookingRef);
      if (!doc.exists) return 'not_found';

      const booking = doc.data();

      if (
        booking.paymentMethod !== 'sepay' ||
        booking.sepayInvoiceNumber !== bookingId
        ) {
        return 'invalid_payment_method';
        }

        if (Number(booking.totalPrice) !== amount) {
        return 'invalid_amount';
        }

      const transactionId = data.transaction?.id;

        if (
        transactionId === undefined ||
        transactionId === null ||
        String(transactionId).trim() === ''
        ) {
        return 'invalid_transaction';
        }

        if (
        booking.paymentStatus === 'paid' ||
        booking.paymentStatus === 'refund_required'
        ) {
        if (booking.sepayTransactionId === String(transactionId)) {
            return 'already_processed';
        }

        return 'different_transaction';
        }

      const selections = booking.selections || [];
      if (!Array.isArray(selections) || !selections.length) {
        return 'invalid_booking';
      }

      const refs = selections.map(s =>
        db.collection('booking_slots').doc(slotId(booking.fieldId, s))
      );

      const slots = await Promise.all(refs.map(ref => tx.get(ref)));

      const expiryMs = booking.expiresAt?.toMillis
        ? booking.expiresAt.toMillis()
        : new Date(booking.expiresAt).getTime();
      const valid =
        booking.status === 'pending_payment' &&
        booking.paymentStatus === 'pending' &&
        Number.isFinite(expiryMs) &&
        expiryMs > Date.now() &&
        slots.every(slot =>
          slot.exists &&
          slot.data().bookingId === bookingId &&
          slot.data().status === 'held'
        );

      const paidAt = new Date().toISOString();

      if (!valid) {
        tx.update(bookingRef, {
          paymentStatus: 'refund_required',
          latePaymentAt: paidAt,
          sepayTransactionId: String(transactionId)
        });
        return 'late_payment';
      }

      tx.update(bookingRef, {
        status: 'confirmed',
        paymentStatus: 'paid',
        paymentMethod: 'sepay',
        paidAt,
        sepayTransactionId: String(transactionId)
      });

      slots.forEach(slot => {
        tx.update(slot.ref, {
          status: 'confirmed',
          expiresAt: null
        });
      });

      return 'confirmed';
    });

    if ([
    'not_found',
    'invalid_amount',
    'invalid_booking',
    'invalid_payment_method',
    'invalid_transaction',
    'different_transaction'
    ].includes(result)) {
    return res.status(400).json({ success: false, result });
    }

    return res.json({ success: true, result });
  } catch (error) {
    console.error('SePay IPN error:', error);
    return res.status(500).json({ success: false });
  }
});


const { SePayPgClient } = require('sepay-pg-node');
const { requireAuth } = require('./authMiddleware');

router.post('/payments/sepay/create', requireAuth, async (req, res) => {
  try {
    const { SEPAY_MERCHANT_ID, SEPAY_SECRET_KEY, PUBLIC_BASE_URL } = process.env;

    if (!SEPAY_MERCHANT_ID || !SEPAY_SECRET_KEY || !PUBLIC_BASE_URL) {
      return res.status(503).json({
        success: false,
        message: 'SePay chưa được cấu hình.'
      });
    }

    const bookingId = req.body?.bookingId;

    if (typeof bookingId !== 'string' ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(bookingId)) {
      return res.status(400).json({
        success: false,
        message: 'Mã đặt sân không hợp lệ.'
      });
    }

    const doc = await db.collection('bookings').doc(bookingId).get();

    if (!doc.exists || doc.data().userId !== req.user.id) {
      return res.status(404).json({
        success: false,
        message: 'Không tìm thấy đơn đặt sân.'
      });
    }

    const booking = doc.data();

    if (
        booking.status !== 'pending_payment' ||
        booking.paymentStatus !== 'pending'
        ) {
        return res.status(409).json({
            success: false,
            message: 'Đơn không thể thanh toán.'
        });
        }

        const expiryMs = booking.expiresAt?.toMillis
        ? booking.expiresAt.toMillis()
        : new Date(booking.expiresAt).getTime();

        if (!Number.isFinite(expiryMs) || expiryMs <= Date.now()) {
        return res.status(409).json({
            success: false,
            message: 'Đơn đặt sân đã hết hạn.'
        });
        }

    if (!Number.isSafeInteger(booking.totalPrice) ||
        booking.totalPrice <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Số tiền thanh toán không hợp lệ.'
      });
    }

    const client = new SePayPgClient({
      merchant_id: SEPAY_MERCHANT_ID,
      secret_key: SEPAY_SECRET_KEY,
      env: 'sandbox'
    });

    const baseUrl = PUBLIC_BASE_URL.replace(/\/$/, '');

    const fields = client.checkout.initOneTimePaymentFields({
      operation: 'PURCHASE',
      payment_method: 'BANK_TRANSFER',
      order_invoice_number: bookingId,
      order_amount: booking.totalPrice,
      currency: 'VND',
      order_description: `Thanh toan dat san SPORTY ${bookingId}`,
      success_url: `${baseUrl}/api/payments/sepay/return`,
      error_url: `${baseUrl}/api/payments/sepay/return`,
      cancel_url: `${baseUrl}/api/payments/sepay/return`
    });

    await db.runTransaction(async (tx) => {
  const fresh = await tx.get(doc.ref);

  if (!fresh.exists) {
    throw new Error('Booking không tồn tại');
  }

  const current = fresh.data();

  const currentExpiryMs = current.expiresAt?.toMillis
    ? current.expiresAt.toMillis()
    : new Date(current.expiresAt).getTime();

  if (
    current.status !== 'pending_payment' ||
    current.paymentStatus !== 'pending' ||
    !Number.isFinite(currentExpiryMs) ||
    currentExpiryMs <= Date.now() ||
    (current.paymentMethod && current.paymentMethod !== 'sepay')
  ) {
    throw new Error('Booking không còn hợp lệ cho SePay');
  }

  tx.update(doc.ref, {
    paymentMethod: 'sepay',
    sepayInvoiceNumber: bookingId
  });
});
    return res.json({
      success: true,
      checkoutUrl: client.checkout.initCheckoutUrl(),
      fields,
      bookingId,
      expiresAt: booking.expiresAt
    });
  } catch (error) {
    console.error('SePay create error:', error);
    return res.status(500).json({
      success: false,
      message: 'Không thể tạo thanh toán SePay.'
    });
  }
});

router.get('/payments/sepay/return', (req, res) => {
  res.type('html').send(`
    <html>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <body style="font-family:sans-serif;text-align:center;padding:35px">
        <h2>Da quay lai tu SePay</h2>
        <p>Mo lai SPORTY de kiem tra trang thai don dat san.</p>
        <p>Chi IPN da xac minh moi co the xac nhan thanh toan.</p>
      </body>
    </html>
  `);
});

// POST /api/payments/sepay/membership/create
router.post(
  '/payments/sepay/membership/create',
  requireAuth,
  async (req, res) => {
    try {
      const {
        SEPAY_MERCHANT_ID,
        SEPAY_SECRET_KEY,
        PUBLIC_BASE_URL
      } = process.env;

      if (!SEPAY_MERCHANT_ID || !SEPAY_SECRET_KEY || !PUBLIC_BASE_URL) {
        return res.status(503).json({
          success: false,
          message: 'SePay chưa được cấu hình.'
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
      const snapshot = await orderRef.get();

      if (
        !snapshot.exists ||
        snapshot.data().userId !== req.user.id
      ) {
        return res.status(404).json({
          success: false,
          message: 'Không tìm thấy đơn hội viên.'
        });
      }

      const order = snapshot.data();

      if (
        order.status !== 'pending_payment' ||
        order.paymentStatus !== 'pending'
      ) {
        return res.status(409).json({
          success: false,
          message: 'Đơn hội viên không thể thanh toán.'
        });
      }

      const expiryMs = order.expiresAt?.toMillis
        ? order.expiresAt.toMillis()
        : new Date(order.expiresAt).getTime();

      if (!Number.isFinite(expiryMs) || expiryMs <= Date.now()) {
        return res.status(409).json({
          success: false,
          message: 'Đơn hội viên đã hết hạn.'
        });
      }

      if (
        !Number.isSafeInteger(order.totalPrice) ||
        order.totalPrice <= 0
      ) {
        return res.status(400).json({
          success: false,
          message: 'Số tiền thanh toán không hợp lệ.'
        });
      }

      const client = new SePayPgClient({
        merchant_id: SEPAY_MERCHANT_ID,
        secret_key: SEPAY_SECRET_KEY,
        env: 'sandbox'
      });

      const baseUrl = PUBLIC_BASE_URL.replace(/\/$/, '');

      // Tiền tố MEM_ để phân biệt hóa đơn hội viên.
      const invoiceNumber = `MEM_${orderId}`;

      const fields = client.checkout.initOneTimePaymentFields({
        operation: 'PURCHASE',
        payment_method: 'BANK_TRANSFER',
        order_invoice_number: invoiceNumber,
        order_amount: order.totalPrice,
        currency: 'VND',
        order_description: `Thanh toan hoi vien SPORTY ${orderId}`,
        success_url: `${baseUrl}/api/payments/sepay/return`,
        error_url: `${baseUrl}/api/payments/sepay/return`,
        cancel_url: `${baseUrl}/api/payments/sepay/return`
      });

      await db.runTransaction(async tx => {
        const fresh = await tx.get(orderRef);

        if (!fresh.exists) {
          throw new Error('Đơn hội viên không tồn tại.');
        }

        const current = fresh.data();

        const currentExpiryMs = current.expiresAt?.toMillis
          ? current.expiresAt.toMillis()
          : new Date(current.expiresAt).getTime();

        if (
          current.userId !== req.user.id ||
          current.status !== 'pending_payment' ||
          current.paymentStatus !== 'pending' ||
          current.totalPrice !== order.totalPrice ||
          !Number.isFinite(currentExpiryMs) ||
          currentExpiryMs <= Date.now() ||
          (current.paymentMethod &&
            current.paymentMethod !== 'sepay')
        ) {
          throw new Error('Đơn không còn hợp lệ cho SePay.');
        }

        tx.update(orderRef, {
          paymentMethod: 'sepay',
          sepayInvoiceNumber: invoiceNumber
        });
      });

      return res.json({
        success: true,
        checkoutUrl: client.checkout.initCheckoutUrl(),
        fields,
        orderId,
        expiresAt: order.expiresAt
      });
    } catch (error) {
      console.error('SePay membership create error:', error);

      return res.status(409).json({
        success: false,
        message: 'Không thể tạo thanh toán hội viên.'
      });
    }
  }
);

module.exports = router;
