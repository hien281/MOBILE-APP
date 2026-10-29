const express = require('express');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');

const router = express.Router();

// Cấu hình riêng của từng cơ sở, lấy từ fields/{fieldId}.
// Mỗi lượt đặt hiện dài 60 phút và bắt đầu tại giờ tròn.
function getFieldSchedule(data) {
  const count = Number(data.courtCount);
  const courtCount = Number.isInteger(count) && count >= 1 && count <= 100
    ? count
    : 1; // Tương thích với cơ sở cũ chưa có courtCount.

  const validTime = value =>
    typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);

  const openingTime = validTime(data.openingTime)
    ? data.openingTime
    : '06:00';
  const closingTime = validTime(data.closingTime)
    ? data.closingTime
    : '22:00';

  const toMinutes = time => {
    const [hour, minute] = time.split(':').map(Number);
    return hour * 60 + minute;
  };
  const open = toMinutes(openingTime);
  const close = toMinutes(closingTime);

  if (close <= open) {
    throw new Error('Giờ hoạt động của cơ sở không hợp lệ.');
  }

  const hours = [];
  for (let hour = 0; hour < 24; hour++) {
    if (hour * 60 >= open && (hour + 1) * 60 <= close) {
      hours.push(`${String(hour).padStart(2, '0')}:00`);
    }
  }

  return {
    courtCount,
    openingTime,
    closingTime,
    courts: Array.from({ length: courtCount }, (_, i) => `court_${i + 1}`),
    hours
  };
}

const MAX_SLOTS = 100;
const PAYMENT_TIMEOUT_MINUTES = 10;
const PAYMENT_TIMEOUT_MS = PAYMENT_TIMEOUT_MINUTES * 60 * 1000;

function validDate(value) {
  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    return false;
  }

  const d = new Date(`${value}T00:00:00Z`);

  return (
    !Number.isNaN(d.getTime()) &&
    d.toISOString().slice(0, 10) === value
  );
}

function endTime(start) {
  return `${String(Number(start.slice(0, 2)) + 1).padStart(2, '0')}:00`;
}

function slotId(fieldId, courtId, date, startTime) {
  return (
    `${fieldId}_${courtId}_${date}_` +
    startTime.replace(':', '-')
  );
}

function normalizedSelections(body) {
  const items = Array.isArray(body.selections)
    ? body.selections
    : [{
        date: body.date,
        courtId: body.courtId || 'court_1',
        startTime: body.startTime
      }];

  if (items.length === 0 || items.length > MAX_SLOTS) {
    return null;
  }

  const seen = new Set();
  const normalized = [];

  for (const item of items) {
    if (
      !item ||
      !validDate(item.date) ||
      typeof item.courtId !== 'string' ||
      !/^court_[1-9]\d*$/.test(item.courtId) ||
      typeof item.startTime !== 'string' ||
      !/^([01]\d|2[0-3]):00$/.test(item.startTime)
    ) {
      return null;
    }

    const key =
      `${item.date}|${item.courtId}|${item.startTime}`;

    if (seen.has(key)) return null;

    seen.add(key);

    normalized.push({
      date: item.date,
      courtId: item.courtId,
      startTime: item.startTime
    });
  }

  return normalized;
}

function expiredHeldSlot(data, nowMs) {
  return (
    data.status === 'held' &&
    typeof data.expiresAt === 'string' &&
    Number.isFinite(Date.parse(data.expiresAt)) &&
    Date.parse(data.expiresAt) <= nowMs
  );
}


router.get('/fields/:id/availability', async (req, res) => {
  try {
    const { id } = req.params;
    const { date } = req.query;

    if (!validDate(date)) {
      return res.status(400).json({
        success: false,
        message: 'Ngày không hợp lệ.'
      });
    }

    const field = await db.collection('fields').doc(id).get();

    if (!field.exists) {
      return res.status(404).json({
        success: false,
        message: 'Không tìm thấy sân.'
      });
    }

    const schedule = getFieldSchedule(field.data());

    const snapshot = await db
      .collection('booking_slots')
      .where('fieldId', '==', id)
      .where('date', '==', date)
      .get();

    const booked = new Set();
    const legacy = new Set();
    const nowMs = Date.now();

    for (const doc of snapshot.docs) {
      const item = doc.data();

      // Bỏ qua slot giữ sân đã hết hạn.
      if (expiredHeldSlot(item, nowMs)) continue;

      if (schedule.courts.includes(item.courtId)) {
        booked.add(`${item.courtId}|${item.startTime}`);
      } else if (!item.courtId) {
        // Booking cũ không lưu courtId: chặn toàn bộ sân ở giờ này.
        legacy.add(item.startTime);
      }
    }

    const courts = schedule.courts.map((courtId, i) => ({
      courtId,
      name: `Sân ${i + 1}`,
      slots: schedule.hours.map(startTime => ({
        startTime,
        available:
          !legacy.has(startTime) &&
          !booked.has(`${courtId}|${startTime}`)
      }))
    }));

    return res.json({
      success: true,
      fieldId: id,
      date,
      courtCount: schedule.courtCount,
      openingTime: schedule.openingTime,
      closingTime: schedule.closingTime,
      courts,
      slots: courts[0]?.slots || []
    });
  } catch (error) {
    console.error('Availability error:', error);

    return res.status(500).json({
      success: false,
      message: 'Không thể kiểm tra lịch trống.'
    });
  }
});

router.post('/bookings', requireAuth, async (req, res) => {
  try {
    const { fieldId } = req.body || {};
    const selections = normalizedSelections(req.body || {});

    if (
      typeof fieldId !== 'string' ||
      !fieldId.trim() ||
      !selections
    ) {
      return res.status(400).json({
        success: false,
        message:
          'Thông tin đặt sân không hợp lệ (tối đa 100 khung giờ).'
      });
    }

    const nowVN = new Date(
      Date.now() + 7 * 60 * 60 * 1000
    ).toISOString().slice(0, 16);

    if (
      selections.some(
        s => `${s.date}T${s.startTime}` <= nowVN
      )
    ) {
      return res.status(400).json({
        success: false,
        message: 'Không thể đặt khung giờ đã qua.'
      });
    }

    const fieldRef = db.collection('fields').doc(fieldId);
    const bookingRef = db.collection('bookings').doc();

    const refs = selections.map(s =>
      db.collection('booking_slots').doc(
        slotId(
          fieldId,
          s.courtId,
          s.date,
          s.startTime
        )
      )
    );

    const legacyRefs = selections.map(s =>
      db.collection('booking_slots').doc(
        `${fieldId}_${s.date}_${s.startTime.replace(':', '-')}`
      )
    );

    const result = await db.runTransaction(async tx => {
      // Firestore: đọc toàn bộ dữ liệu trước khi ghi.
      const field = await tx.get(fieldRef);

      const slots = await Promise.all(
        refs.map(ref => tx.get(ref))
      );

      const legacySlots = await Promise.all(
        legacyRefs.map(ref => tx.get(ref))
      );

      if (!field.exists) {
        return {
          status: 404,
          message: 'Không tìm thấy sân.'
        };
      }

      const schedule = getFieldSchedule(field.data());
      if (selections.some(s =>
        !schedule.courts.includes(s.courtId) ||
        !schedule.hours.includes(s.startTime)
      )) {
        return {
          status: 400,
          message: 'Sân hoặc khung giờ nằm ngoài lịch hoạt động của cơ sở.'
        };
      }

      if (legacySlots.some(s => s.exists)) {
        return {
          status: 409,
          message: 'Khung giờ đã có lịch đặt cũ.'
        };
      }

      const nowMs = Date.now();
      const expiredOwners = new Map();

      for (const slot of slots) {
        if (!slot.exists) continue;

        const data = slot.data();

        if (
          !expiredHeldSlot(data, nowMs) ||
          typeof data.bookingId !== 'string' ||
          !data.bookingId
        ) {
          return {
            status: 409,
            message:
              'Có khung giờ đã được đặt. Hãy tải lại lịch.'
          };
        }

        expiredOwners.set(
          data.bookingId,
          db.collection('bookings').doc(data.bookingId)
        );
      }

      const ownerDocs = await Promise.all(
        [...expiredOwners.values()].map(
          ref => tx.get(ref)
        )
      );

      for (const owner of ownerDocs) {
        if (
          !owner.exists ||
          owner.data().status !== 'pending_payment' ||
          typeof owner.data().expiresAt !== 'string' ||
          !Number.isFinite(
            Date.parse(owner.data().expiresAt)
          ) ||
          Date.parse(owner.data().expiresAt) > nowMs
        ) {
          return {
            status: 409,
            message:
              'Khung giờ đang được xử lý thanh toán.'
          };
        }
      }

      const price = field.data().price;

      if (
        typeof price !== 'number' ||
        !Number.isFinite(price) ||
        price < 0
      ) {
        return {
          status: 500,
          message:
            'Giá sân chưa được cấu hình hợp lệ.'
        };
      }

      const createdAt = new Date(nowMs).toISOString();

      const expiresAt = new Date(
        nowMs + PAYMENT_TIMEOUT_MS
      ).toISOString();

      const booking = {
        fieldId,
        userId: req.user.id,
        type:
          selections.length > 1 ? 'multi' : 'single',
        selections: selections.map(s => ({
          ...s,
          endTime: endTime(s.startTime)
        })),
        totalPrice: price * selections.length,
        status: 'pending_payment',
        paymentStatus: 'pending',
        createdAt,
        expiresAt
      };

      if (selections.length === 1) {
        Object.assign(booking, {
          ...selections[0],
          endTime: endTime(selections[0].startTime)
        });
      }

      ownerDocs.forEach(doc => {
        tx.update(doc.ref, {
          status: 'expired',
          paymentStatus: 'expired'
        });
      });

      tx.create(bookingRef, booking);

      refs.forEach((ref, i) => {
        const data = {
          bookingId: bookingRef.id,
          fieldId,
          ...selections[i],
          status: 'held',
          expiresAt
        };

        if (slots[i].exists) {
          tx.set(ref, data);
        } else {
          tx.create(ref, data);
        }
      });

      return {
        success: true,
        bookingId: bookingRef.id,
        booking,
        expiresAt,
        remainingSeconds:
          PAYMENT_TIMEOUT_MINUTES * 60
      };
    });

    if (result.status) {
      return res.status(result.status).json({
        success: false,
        message: result.message
      });
    }

    return res.status(201).json(result);
  } catch (error) {
    console.error('Booking error:', error);

    return res.status(500).json({
      success: false,
      message:
        'Không thể tạo đơn chờ thanh toán.'
    });
  }
});


router.post(
  '/bookings/:id/cancel',
  requireAuth,
  async (req, res) => {
    try {
      const bookingRef = db
        .collection('bookings')
        .doc(req.params.id);

      const result = await db.runTransaction(async tx => {
        const bookingDoc = await tx.get(bookingRef);

        if (!bookingDoc.exists) {
          return {
            code: 404,
            message: 'Không tìm thấy đơn.'
          };
        }

        const booking = bookingDoc.data();

        if (booking.userId !== req.user.id) {
          return {
            code: 403,
            message:
              'Bạn không có quyền hủy đơn này.'
          };
        }

        if (booking.status === 'cancelled') {
          return {
            success: true,
            status: 'cancelled'
          };
        }

        if (
          booking.status !== 'pending_payment' ||
          booking.paymentStatus !== 'pending'
        ) {
          return {
            code: 409,
            message:
              'Đơn không còn ở trạng thái chờ thanh toán, không thể hủy.'
          };
        }

        const selections =
          Array.isArray(booking.selections)
            ? booking.selections
            : [];

        if (!selections.length) {
          return {
            code: 409,
            message:
              'Đơn thiếu thông tin khung giờ.'
          };
        }

        const slotRefs = selections.map(s =>
          db.collection('booking_slots').doc(
            slotId(
              booking.fieldId,
              s.courtId,
              s.date,
              s.startTime
            )
          )
        );

        // Đọc tất cả slot trước khi ghi.
        const slotDocs = await Promise.all(
          slotRefs.map(ref => tx.get(ref))
        );

        tx.update(bookingRef, {
          status: 'cancelled',
          paymentStatus: 'cancelled',
          cancelledAt: new Date().toISOString()
        });

        slotDocs.forEach(doc => {
          // Chỉ xóa slot thuộc chính đơn này.
          if (
            doc.exists &&
            doc.data().bookingId === bookingDoc.id
          ) {
            tx.delete(doc.ref);
          }
        });

        return {
          success: true,
          status: 'cancelled'
        };
      });

      if (result.code) {
        return res.status(result.code).json({
          success: false,
          message: result.message
        });
      }

      return res.json(result);
    } catch (error) {
      console.error('Cancel booking error:', error);

      return res.status(500).json({
        success: false,
        message: 'Không thể hủy giữ sân.'
      });
    }
  }
);


// Ghi nhận yêu cầu xem xét hoàn tiền; KHÔNG tự động hoàn tiền hay nhả sân.
router.post('/bookings/:id/refund-request', requireAuth, async (req, res) => {
  try {
    const ref = db.collection('bookings').doc(req.params.id);
    const result = await db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (!doc.exists) return {code:404, message:'Không tìm thấy đơn.'};
      const b = doc.data();
      if (b.userId !== req.user.id) return {code:403, message:'Không có quyền truy cập đơn.'};
      if (b.bookingType === 'membership' || b.paymentStatus !== 'paid' ||
          !['confirmed','booked'].includes(b.status)) {
        return {code:409, message:'Đơn không đủ điều kiện gửi yêu cầu hoàn tiền.'};
      }
      const requestedKey = req.body?.sessionKey;
      if (requestedKey != null) {
        if (typeof requestedKey !== 'string' || !/^\d{4}-\d{2}-\d{2}\|court_[1-9]\d*$/.test(requestedKey))
          return {code:400,message:'Buổi cần huỷ không hợp lệ.'};
        const selected = (Array.isArray(b.selections)?b.selections:[]).filter(s=>s.date+'|'+s.courtId===requestedKey);
        if (!selected.length) return {code:404,message:'Không tìm thấy buổi trong đơn.'};
        const starts = selected.map(s=>Date.parse(s.date+'T'+s.startTime+':00+07:00'));
        if (starts.some(t=>!Number.isFinite(t)) || Math.min(...starts)-Date.now()<24*3600000)
          return {code:409,message:'Chỉ hoàn tiền khi yêu cầu trước giờ chơi ít nhất 24 tiếng.'};
        const key=requestedKey.replace('|','__');
        const existing = b.refundSessionRequests||{};
        if (existing[key]) return {success:true,status:existing[key].status};
        const all = Array.isArray(b.selections)?b.selections:[];
        const amount = Math.round(Number(b.totalPrice)*selected.length/all.length);
        if (!Number.isFinite(amount)||amount<=0) return {code:409,message:'Không xác định được số tiền hoàn.'};
        tx.update(ref,{['refundSessionRequests.'+key]:{status:'pending',requestedAt:new Date().toISOString(),amount,policy:'full_before_24h',sessionKey:requestedKey}});
        return {success:true,status:'pending',refundAmount:amount};
      }
      if (b.refundRequestStatus === 'pending') return {success:true, status:'pending'};
      if (b.refundRequestStatus) return {code:409, message:'Yêu cầu đã được xử lý trước đó.'};
      const selections = Array.isArray(b.selections) ? b.selections : [];
      const starts = selections.map(s => Date.parse(s.date+'T'+s.startTime+':00+07:00'));
      if (!starts.length || starts.some(t => !Number.isFinite(t))) {
        return {code:409, message:'Đơn thiếu thời gian đặt sân hợp lệ.'};
      }
      const hoursUntilStart = (Math.min(...starts) - Date.now()) / 3600000;
      if (hoursUntilStart < 24) {
        return {code:409, message:'Chỉ được yêu cầu huỷ và hoàn 100% trước giờ bắt đầu ít nhất 24 tiếng.'};
      }
      const refundAmount = Number(b.totalPrice);
      if (!Number.isFinite(refundAmount) || refundAmount <= 0) {
        return {code:409, message:'Số tiền thanh toán không hợp lệ.'};
      }
      tx.update(ref, {
        refundRequestStatus:'pending',
        refundRequestedAt:new Date().toISOString(),
        refundPolicy:'full_before_24h',
        refundPercent:100,
        refundAmount,
      });
      return {success:true, status:'pending'};
    });
    if (result.code) return res.status(result.code).json({success:false,message:result.message});
    return res.json(result);
  } catch (error) {
    console.error('Refund request:',error);
    return res.status(500).json({success:false,message:'Không gửi được yêu cầu.'});
  }
});

router.get(
  '/bookings/:id/status',
  requireAuth,
  async (req, res) => {
    try {
      const bookingDoc = await db
        .collection('bookings')
        .doc(req.params.id)
        .get();

      if (!bookingDoc.exists) {
        return res.status(404).json({
          success: false,
          message:
            'Không tìm thấy đơn đặt sân.'
        });
      }

      const booking = bookingDoc.data();

      if (booking.userId !== req.user.id) {
        return res.status(403).json({
          success: false,
          message:
            'Bạn không có quyền xem đơn này.'
        });
      }

      const expiresAt = booking.expiresAt || null;

      const remainingSeconds = expiresAt
        ? Math.max(
            0,
            Math.ceil(
              (
                new Date(expiresAt).getTime() -
                Date.now()
              ) / 1000
            )
          )
        : null;

      return res.json({
        success: true,
        bookingId: bookingDoc.id,
        status: booking.status,
        paymentStatus:
          booking.paymentStatus || null,
        totalPrice: booking.totalPrice,
        expiresAt,
        remainingSeconds,
        serverTime: new Date().toISOString()
      });
    } catch (error) {
      console.error(
        'Booking status error:',
        error
      );

      return res.status(500).json({
        success: false,
        message:
          'Không thể kiểm tra trạng thái đơn hàng.'
      });
    }
  }
);

module.exports = router;
