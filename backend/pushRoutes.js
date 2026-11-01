const express = require('express');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');
const router = express.Router();

const hashToken = token => crypto.createHash('sha256').update(token).digest('hex');
const validToken = t => typeof t === 'string' && t.length >= 30 && t.length <= 4096;
const VN_OFFSET_MS = 7 * 60 * 60 * 1000;

router.post('/push/register', requireAuth, async (req, res) => {
  try {
    const token = req.body?.token;
    if (!validToken(token)) return res.status(400).json({success:false,message:'FCM token không hợp lệ.'});
    const tokenId=hashToken(token);
    const ownerRef=db.collection('push_token_owners').doc(tokenId);
    const batch = db.batch();
    batch.set(ownerRef, {
      userId: req.user.id,
      updatedAt: FieldValue.serverTimestamp()
    });
    batch.set(
      db.collection('user_push_tokens').doc(req.user.id)
        .collection('devices').doc(tokenId),
      {token, updatedAt: FieldValue.serverTimestamp()}
    );
    await batch.commit();
    res.json({success:true});
  } catch (error) {
    console.error('Push registration failed:', {
      code: error?.code,
      message: error?.message,
      stack: error?.stack
    });
    res.status(500).json({success:false,message:'Không lưu được thiết bị.'});
  }
});

router.post('/push/unregister', requireAuth, async (req, res) => {
  try {
    const token = req.body?.token;
    if (!validToken(token)) return res.status(400).json({success:false});
    const tokenId=hashToken(token);
    await db.collection('user_push_tokens').doc(req.user.id)
      .collection('devices').doc(tokenId).delete();
    const ownerRef=db.collection('push_token_owners').doc(tokenId);
    const owner=await ownerRef.get();
    if(owner.exists && owner.data()?.userId===req.user.id) await ownerRef.delete();
    res.json({success:true});
  } catch(error) {
    console.error('Push unregister:',error);
    res.status(500).json({success:false});
  }
});

function vnDateAndTime(value) {
  const d = new Date(value + VN_OFFSET_MS);
  return {
    date: d.toISOString().slice(0,10),
    time: d.toISOString().slice(11,16)
  };
}
function slotStartMs(s) {
  if (!s || typeof s.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s.date) ||
      typeof s.startTime !== 'string' || !/^\d{2}:\d{2}$/.test(s.startTime)) return NaN;
  return Date.parse(`${s.date}T${s.startTime}:00+07:00`);
}
function isConfirmed(b) {
  return (b.status === 'confirmed' || b.status === 'booked') &&
    (b.bookingType === 'membership' || b.paymentStatus === 'paid');
}

// Được gọi bởi cron bên ngoài, mỗi 5 phút. Không dành cho người dùng thông thường.
router.get('/internal/send-booking-reminders', async (req,res) => {
  const secret = process.env.CRON_SECRET;
  const authorization = req.get('authorization') || '';
  if (!secret || authorization !== `Bearer ${secret}`) return res.sendStatus(401);
  try {
    const now = Date.now();
    const earliest = now + 55 * 60 * 1000;
    const latest = now + 60 * 60 * 1000;
    const days = new Set([vnDateAndTime(earliest).date, vnDateAndTime(latest).date]);
    // Query theo status, rồi lọc từng buổi; dự án nhỏ phù hợp cách này.
    const snapshot = await db.collection('bookings').where('status','==','confirmed').get();
    const fields = new Map();
    const tokenCache = new Map();
    let matched=0, sent=0, skipped=0, errors=0;
    for(const bookingDoc of snapshot.docs) {
      const b = bookingDoc.data();
      if(!isConfirmed(b) || !b.userId) continue;
      const sessions = Array.isArray(b.selections) && b.selections.length
        ? b.selections : (b.date ? [b] : []);
      const excluded = new Set(Array.isArray(b.cancelledSessions) ? b.cancelledSessions : []);
      for(const s of sessions) {
        if(!days.has(s.date) || !s.courtId || !s.startTime) continue;
        if(excluded.has(`${s.date}|${s.courtId}`)) continue;
        const starts = slotStartMs(s);
        if(!Number.isFinite(starts) || starts < earliest || starts > latest) continue;
        matched++;
        const reminderId = crypto.createHash('sha256')
          .update(JSON.stringify([bookingDoc.id,s.date,s.courtId,s.startTime]))
          .digest('hex');
        const reminderRef = db.collection('booking_reminders').doc(reminderId);
        // Atomic claim: cron chạy song song không phát trùng.
        try { await reminderRef.create({
          bookingId:bookingDoc.id, userId:b.userId, date:s.date, startTime:s.startTime,
          status:'processing', createdAt:FieldValue.serverTimestamp()
        }); } catch(e) { if(e.code===6 || e.code==='already-exists') {skipped++;continue;} throw e; }
        try {
          if(!tokenCache.has(b.userId)) {
            const devices = await db.collection('user_push_tokens').doc(b.userId).collection('devices').get();
            tokenCache.set(b.userId, devices.docs.map(d=>({ref:d.ref,token:d.data().token})).filter(d=>validToken(d.token)));
          }
          const candidateDevices = tokenCache.get(b.userId);
          const devices = [];
          for(const device of candidateDevices) {
            const owner=await db.collection('push_token_owners').doc(hashToken(device.token)).get();
            if(owner.exists && owner.data()?.userId===b.userId) devices.push(device);
          }
          if(!devices.length) {
            await reminderRef.update({status:'no_device'});
            skipped++; continue;
          }
          if(!fields.has(b.fieldId)) {
            const doc=await db.collection('fields').doc(String(b.fieldId)).get();
            fields.set(b.fieldId,doc.exists?doc.data().name:'sân đã đặt');
          }
          const venue=fields.get(b.fieldId)||'sân đã đặt';
          const court = s.courtId.replace(/^court_/, 'Sân ');
          const message = {
            notification: {title:'SPORTY · Sắp đến giờ chơi!',body:`Còn khoảng 1 tiếng: ${venue}, ${court}, lúc ${s.startTime} ngày ${s.date}.`},
            data:{type:'booking_reminder',bookingId:bookingDoc.id,date:s.date,courtId:String(s.courtId)},
            tokens:devices.map(d=>d.token),
            android:{priority:'high'},
          };
          const response=await admin.messaging().sendEachForMulticast(message);
          for(let i=0;i<response.responses.length;i++){
            const result=response.responses[i];
            if (!result.success && /registration-token-not-registered|invalid-registration-token/.test(result.error?.code||'')) {
              await devices[i].ref.delete().catch(()=>{});
            }
          }
          await reminderRef.update({status:response.successCount?'sent':'failed',successCount:response.successCount, failureCount:response.failureCount, completedAt:FieldValue.serverTimestamp()});
          sent+=response.successCount;
          errors+=response.failureCount;
        }catch(e){
          errors++;
          console.error('Reminder send error:',e);
          await reminderRef.update({status:'failed',error:String(e).slice(0,300)}).catch(()=>{});
        }
      }
    }
    res.json({success:true,matched,sent,skipped,errors});
  } catch(e) {
    console.error('Reminder cron:',e);
    res.status(500).json({success:false,message:'Không gửi được nhắc lịch.'});
  }
});
module.exports=router;
