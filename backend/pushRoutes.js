const express = require('express');
const crypto = require('crypto');
const { getMessaging } = require('firebase-admin/messaging');
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
    const tokenId = hashToken(token);
    const ownerRef = db.collection('push_token_owners').doc(tokenId);
    const batch = db.batch();
    batch.set(ownerRef, {userId:req.user.id,updatedAt:FieldValue.serverTimestamp()});
    batch.set(db.collection('user_push_tokens').doc(req.user.id).collection('devices').doc(tokenId),
      {token,updatedAt:FieldValue.serverTimestamp()});
    await batch.commit();
    res.json({success:true});
  } catch(error) {
    console.error('Push registration failed:', error);
    res.status(500).json({success:false,message:'Không lưu được thiết bị.'});
  }
});

router.post('/push/unregister', requireAuth, async (req,res) => {
  try {
    const token=req.body?.token;
    if(!validToken(token))return res.status(400).json({success:false});
    const tokenId=hashToken(token);
    await db.collection('user_push_tokens').doc(req.user.id).collection('devices').doc(tokenId).delete();
    const ownerRef=db.collection('push_token_owners').doc(tokenId);
    const owner=await ownerRef.get();
    if(owner.exists && owner.data()?.userId===req.user.id)await ownerRef.delete();
    res.json({success:true});
  } catch(error){console.error('Push unregister:',error);res.status(500).json({success:false});}
});

function vnDateAndTime(value) {
  const d=new Date(value+VN_OFFSET_MS);
  return {date:d.toISOString().slice(0,10),time:d.toISOString().slice(11,16)};
}
function slotStartMs(s) {
  if(!s || typeof s.date!=='string' || !/^\d{4}-\d{2}-\d{2}$/.test(s.date) ||
     typeof s.startTime!=='string' || !/^\d{2}:\d{2}$/.test(s.startTime))return NaN;
  return Date.parse(`${s.date}T${s.startTime}:00+07:00`);
}
function isConfirmed(b) {
  return (b.status==='confirmed' || b.status==='booked') &&
    (b.bookingType==='membership' || b.paymentStatus==='paid');
}

router.get('/notifications',requireAuth,async(req,res)=>{
  try {
    const snap=await db.collection('user_notifications').doc(req.user.id)
      .collection('items').orderBy('createdAt','desc').limit(100).get();
    res.json({success:true,notifications:snap.docs.map(d=>({id:d.id,...d.data(),createdAt:d.data().createdAt?.toDate?.()?.toISOString()||null}))});
  }catch(error){console.error('List notifications:',error);res.status(500).json({success:false,message:'Không tải được thông báo.'});}
});
router.post('/notifications/:id/read',requireAuth,async(req,res)=>{
  try {
    const id=req.params.id;
    if(!/^[a-f0-9]{64}$/.test(id))return res.sendStatus(400);
    const ref=db.collection('user_notifications').doc(req.user.id).collection('items').doc(id);
    const snap=await ref.get();
    if(!snap.exists)return res.sendStatus(404);
    await ref.update({read:true,readAt:FieldValue.serverTimestamp()});
    res.json({success:true});
  }catch(error){console.error('Read notification:',error);res.status(500).json({success:false});}
});
router.post('/notifications/read-all',requireAuth,async(req,res)=>{
  try {
    const snap=await db.collection('user_notifications').doc(req.user.id)
      .collection('items').where('read','==',false).limit(100).get();
    if(snap.empty)return res.json({success:true,updated:0});
    const batch=db.batch();
    snap.docs.forEach(d=>batch.update(d.ref,{read:true,readAt:FieldValue.serverTimestamp()}));
    await batch.commit();
    res.json({success:true,updated:snap.size});
  }catch(error){console.error('Read all:',error);res.status(500).json({success:false});}
});

// Remove notifications only from the signed-in user's own inbox.
router.delete('/notifications/:id',requireAuth,async(req,res)=>{
  try {
    const id=req.params.id;
    if(!/^[a-f0-9]{64}$/.test(id))return res.status(400).json({success:false,message:'Mã thông báo không hợp lệ.'});
    const ref=db.collection('user_notifications').doc(req.user.id).collection('items').doc(id);
    const snap=await ref.get();
    if(!snap.exists)return res.status(404).json({success:false,message:'Thông báo đã được xoá.'});
    await ref.delete();
    res.json({success:true,deleted:1});
  }catch(error){
    console.error('Delete notification:',error);
    res.status(500).json({success:false,message:'Không xoá được thông báo.'});
  }
});

// Paginate deletes so it works beyond Firestore's per-batch write limit.
router.delete('/notifications',requireAuth,async(req,res)=>{
  try {
    const collection=db.collection('user_notifications').doc(req.user.id).collection('items');
    let deleted=0;
    while(true){
      const snapshot=await collection.limit(400).get();
      if(snapshot.empty)break;
      const batch=db.batch();
      snapshot.docs.forEach(d=>batch.delete(d.ref));
      await batch.commit();
      deleted+=snapshot.size;
      if(snapshot.size<400)break;
    }
    res.json({success:true,deleted});
  }catch(error){
    console.error('Delete all notifications:',error);
    res.status(500).json({success:false,message:'Không xoá được tất cả thông báo. Hãy thử lại.'});
  }
});

// Scheduler should call this every 5 minutes. Covers short delays, but does not promise exact-minute delivery.
router.get('/internal/send-booking-reminders',async(req,res)=>{
  const secret=process.env.CRON_SECRET;
  if(!secret || req.get('authorization')!==`Bearer ${secret}`)return res.sendStatus(401);
  try {
    const now=Date.now();
    const earliest=now+40*60*1000;
    const latest=now+60*60*1000;
    const days=new Set([vnDateAndTime(earliest).date,vnDateAndTime(latest).date]);
    const snapshot=await db.collection('bookings').where('status','==','confirmed').get();
    const fields=new Map();
    const tokenCache=new Map();
    let matched=0,sent=0,skipped=0,errors=0,stored=0;
    for(const bookingDoc of snapshot.docs){
      const b=bookingDoc.data();
      if(!isConfirmed(b)||!b.userId)continue;
      const sessions=Array.isArray(b.selections)&&b.selections.length?b.selections:(b.date?[b]:[]);
      const excluded=new Set(Array.isArray(b.cancelledSessions)?b.cancelledSessions:[]);
      for(const s of sessions){
        if(!days.has(s.date)||!s.courtId||!s.startTime)continue;
        if(excluded.has(`${s.date}|${s.courtId}`))continue;
        const starts=slotStartMs(s);
        if(!Number.isFinite(starts)||starts<earliest||starts>latest)continue;
        matched++;
        const reminderId=crypto.createHash('sha256')
          .update(JSON.stringify([bookingDoc.id,s.date,s.courtId,s.startTime])).digest('hex');
        const reminderRef=db.collection('booking_reminders').doc(reminderId);
        try {
          await reminderRef.create({bookingId:bookingDoc.id,userId:b.userId,date:s.date,
            startTime:s.startTime,status:'processing',createdAt:FieldValue.serverTimestamp()});
        }catch(e){if(e.code===6||e.code==='already-exists'){skipped++;continue;}throw e;}
        try {
          if(!fields.has(b.fieldId)){
            const fieldDoc=await db.collection('fields').doc(String(b.fieldId)).get();
            fields.set(b.fieldId,fieldDoc.exists?fieldDoc.data().name:'sân đã đặt');
          }
          const venue=fields.get(b.fieldId)||'sân đã đặt';
          const court=s.courtId.replace(/^court_/,'Sân ');
          const title='SPORTY · Sắp đến giờ chơi!';
          const body=`Còn khoảng 1 tiếng: ${venue}, ${court}, lúc ${s.startTime} ngày ${s.date}.`;
          const inboxRef=db.collection('user_notifications').doc(b.userId).collection('items').doc(reminderId);
          await inboxRef.set({title,body,bookingId:bookingDoc.id,date:s.date,courtId:String(s.courtId),
            startTime:s.startTime,type:'booking_reminder',read:false,createdAt:FieldValue.serverTimestamp()});
          stored++;
          if(!tokenCache.has(b.userId)){
            const devicesSnap=await db.collection('user_push_tokens').doc(b.userId).collection('devices').get();
            tokenCache.set(b.userId,devicesSnap.docs.map(d=>({ref:d.ref,token:d.data().token})).filter(d=>validToken(d.token)));
          }
          const devices=[];
          for(const device of tokenCache.get(b.userId)){
            const owner=await db.collection('push_token_owners').doc(hashToken(device.token)).get();
            if(owner.exists&&owner.data()?.userId===b.userId)devices.push(device);
          }
          if(!devices.length){
            await reminderRef.update({status:'stored_no_device',completedAt:FieldValue.serverTimestamp()});
            skipped++;continue;
          }
          const message={notification:{title,body},data:{type:'booking_reminder',bookingId:bookingDoc.id,
            date:s.date,courtId:String(s.courtId)},tokens:devices.map(d=>d.token),android:{priority:'high'}};
          const response=await getMessaging().sendEachForMulticast(message);
          for(let i=0;i<response.responses.length;i++){
            const result=response.responses[i];
            if(!result.success && /registration-token-not-registered|invalid-registration-token/.test(result.error?.code||'')){
              await devices[i].ref.delete().catch(()=>{});
            }
          }
          await reminderRef.update({status:response.successCount?'sent':'failed',successCount:response.successCount,
            failureCount:response.failureCount,completedAt:FieldValue.serverTimestamp()});
          sent+=response.successCount;
          errors+=response.failureCount;
        }catch(e){
          errors++;
          console.error('Reminder send error:',e);
          await reminderRef.update({status:'failed',error:String(e).slice(0,300)}).catch(()=>{});
        }
      }
    }
    res.json({success:true,matched,sent,skipped,errors,stored});
  }catch(e){console.error('Reminder cron:',e);res.status(500).json({success:false,message:'Không gửi được nhắc lịch.'});}
});
module.exports=router;
