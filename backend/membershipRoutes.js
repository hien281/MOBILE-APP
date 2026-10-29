const express = require('express');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');

const router = express.Router();

const PAYMENT_TIMEOUT_MS = 15 * 60 * 1000;

// POST /api/membership-orders
router.post('/membership-orders', requireAuth, async (req, res) => {
  try {
    const { membershipId } = req.body || {};

    if (
      typeof membershipId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(membershipId)
    ) {
      return res.status(400).json({
        success: false,
        message: 'Mã gói hội viên không hợp lệ.'
      });
    }

    const membershipRef = db
      .collection('memberships')
      .doc(membershipId);

    const orderRef = db
      .collection('membership_orders')
      .doc();

    const result = await db.runTransaction(async tx => {
      const membershipDoc = await tx.get(membershipRef);

      if (!membershipDoc.exists) {
        return {
          error: 'Không tìm thấy gói hội viên.',
          code: 404
        };
      }

      const membership = membershipDoc.data();

      if (membership.isActive === false) {
        return {
          error: 'Gói hội viên hiện không được mở bán.',
          code: 409
        };
      }

      const price = membership.price;
      const freeSlots = Number(membership.freeSlots);

    const durationMatch = /^(\d+)\s*Tháng$/i.exec(
    String(membership.duration || '').trim()
    );

    const durationMonths = durationMatch
    ? Number(durationMatch[1])
    : null;

    if (
    !Number.isSafeInteger(freeSlots) ||
    freeSlots < 0 ||
    !Number.isSafeInteger(durationMonths) ||
    durationMonths < 1 ||
    durationMonths > 24
    ) {
    return {
        error: 'Quyền lợi hoặc thời hạn gói hội viên không hợp lệ.',
        code: 400
    };
    }

      if (
        !Number.isSafeInteger(price) ||
        price <= 0
      ) {
        return {
          error: 'Giá gói hội viên không hợp lệ.',
          code: 400
        };
      }

      const now = new Date();
      const expiresAt = new Date(
        now.getTime() + PAYMENT_TIMEOUT_MS
      );

      const order = {
        userId: req.user.id,
        membershipId,
        fieldId: membership.fieldId || null,
        membershipName: membership.cardName || '',
        venue: membership.venue || '',
        totalPrice: price,
        status: 'pending_payment',
        paymentStatus: 'pending',
        paymentMethod: null,
        createdAt: now.toISOString(),
        expiresAt: expiresAt.toISOString(),
        freeSlots,
        durationMonths,
      };

      tx.create(orderRef, order);

      return {
        success: true,
        orderId: orderRef.id,
        totalPrice: price,
        membershipName: order.membershipName,
        expiresAt: order.expiresAt
      };
    });

    if (result.error) {
      return res.status(result.code).json({
        success: false,
        message: result.error
      });
    }

    return res.status(201).json(result);
  } catch (error) {
    console.error('Create membership order error:', error);

    return res.status(500).json({
      success: false,
      message: 'Không thể tạo đơn mua thẻ hội viên.'
    });
  }
});

// GET /api/membership-orders/:id/status
router.get(
  '/membership-orders/:id/status',
  requireAuth,
  async (req, res) => {
    try {
      const doc = await db
        .collection('membership_orders')
        .doc(req.params.id)
        .get();

      if (!doc.exists || doc.data().userId !== req.user.id) {
        return res.status(404).json({
          success: false,
          message: 'Không tìm thấy đơn hội viên.'
        });
      }

      const order = doc.data();

      return res.json({
        success: true,
        orderId: doc.id,
        status: order.status,
        paymentStatus: order.paymentStatus,
        totalPrice: order.totalPrice,
        expiresAt: order.expiresAt
      });
    } catch (error) {
      console.error('Membership status error:', error);

      return res.status(500).json({
        success: false,
        message: 'Không thể kiểm tra trạng thái đơn.'
      });
    }
  }
);

module.exports = router;