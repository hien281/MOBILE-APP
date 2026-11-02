const express = require('express');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue } = require('firebase-admin/firestore');
const { db } = require('./firebase');
const router = express.Router();

async function adminOnly(req, res, next) {
  const token = /^Bearer (.+)$/.exec(req.get('authorization') || '')?.[1];
  if (!token) return res.status(401).json({ success:false, message:'Vui lòng đăng nhập.' });
  try {
    const user = await getAuth().verifyIdToken(token, true);
    const allowed = (process.env.SPORTY_ADMIN_UIDS || '').split(',').map(s=>s.trim()).filter(Boolean);
    if (!allowed.includes(user.uid) && user.admin !== true) return res.status(403).json({success:false,message:'Tài khoản không có quyền quản trị.'});
    req.adminUid = user.uid;
    next();
  } catch(e) { res.status(401).json({success:false,message:'Phiên đăng nhập không hợp lệ.'}); }
}
router.use('/admin',adminOnly);
const fail = (res,e) => { console.error('ADMIN API:',e); return res.status(500).json({success:false,message:'Không xử lý được yêu cầu.'}); };
const clean = v => typeof v === 'string' ? v.trim() : '';
const timeOK = t => /^([01]\d|2[0-3]):[0-5]\d$/.test(t);
const mins = t => Number(t.slice(0,2))*60+Number(t.slice(3));
const jsonDoc = d => ({id:d.id,...d.data()});
const asDate = value => value?.toDate?.()?.toISOString?.() || value || null;

router.get('/admin/overview', async(req,res)=>{
 try {
  const [fields,bookings,users] = await Promise.all([
    db.collection('fields').get(),db.collection('bookings').get(),db.collection('users').get()
  ]);
  let totalPaid=0, confirmed=0, sessions=0;
  const perDay={};
  const customerIds=new Set();
  for(const d of bookings.docs){
   const b=d.data(); if(b.userId)customerIds.add(b.userId);
   if(b.status==='confirmed'){confirmed++; const ss=Array.isArray(b.selections)&&b.selections.length?b.selections:[b];sessions+=ss.length;
    for(const s of ss){if(/^\d{4}-\d{2}-\d{2}$/.test(s.date||''))perDay[s.date]=(perDay[s.date]||0)+1;}
   }
   if(b.paymentStatus==='paid' && b.bookingType!=='membership')totalPaid+=Number(b.totalPrice)||0;
  }
  res.json({success:true,stats:{fields:fields.size,registeredUsers:users.size,bookingCustomers:customerIds.size,orders:bookings.size,confirmed,sessions,paidRevenue:totalPaid},chart:Object.entries(perDay).sort(([a],[b])=>a.localeCompare(b)).slice(-14).map(([date,count])=>({date,count}))});
 }catch(e){fail(res,e)}
});
router.get('/admin/bookings',async(req,res)=>{
 try {
  const snap=await db.collection('bookings').orderBy('createdAt','desc').limit(400).get();
  const rows=snap.docs.map(d=>{const b=jsonDoc(d);return {...b,createdAt:asDate(b.createdAt),confirmedAt:asDate(b.confirmedAt)};});
  res.json({success:true,bookings:rows});
 }catch(e){fail(res,e)}
});
router.get('/admin/fields',async(req,res)=>{
 try {const snap=await db.collection('fields').get();res.json({success:true,fields:snap.docs.map(jsonDoc)});}catch(e){fail(res,e)}
});
function validInput(body){
 const name=clean(body.name), address=clean(body.address), sport=clean(body.sport);
 const openingTime=clean(body.openingTime),closingTime=clean(body.closingTime);
 const price=Number(body.price),courtCount=Number(body.courtCount);
 if(!name||name.length>150||!address||address.length>350||!['Bóng đá','Cầu lông','Tennis','Pickleball'].includes(sport))return null;
 if(!timeOK(openingTime)||!timeOK(closingTime)||mins(openingTime)>=mins(closingTime))return null;
 if(!Number.isSafeInteger(price)||price<0||price>100000000||!Number.isInteger(courtCount)||courtCount<1||courtCount>100)return null;
 return {name,address,sport,openingTime,closingTime,price,courtCount};
}
router.post('/admin/fields',async(req,res)=>{
 try {const data=validInput(req.body||{});if(!data)return res.status(400).json({success:false,message:'Thông tin sân chưa hợp lệ.'});
  const ref=await db.collection('fields').add({...data,isActive:true,createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});
  res.status(201).json({success:true,id:ref.id});
 }catch(e){fail(res,e)}
});
router.put('/admin/fields/:id',async(req,res)=>{
 try {
  const ref=db.collection('fields').doc(req.params.id);const snap=await ref.get();if(!snap.exists)return res.status(404).json({success:false,message:'Không tìm thấy sân.'});
  const data=validInput(req.body||{});if(!data)return res.status(400).json({success:false,message:'Thông tin sân chưa hợp lệ.'});
  // Do not remove existing confirmed sessions by reducing operating hours or court count.
  const bookings=await db.collection('bookings').where('fieldId','==',req.params.id).where('status','==','confirmed').get();
  const now=new Date().toISOString().slice(0,10);
  for(const b of bookings.docs){const raw=b.data();const cancelled=new Set(raw.cancelledSessions||[]);const ss=Array.isArray(raw.selections)&&raw.selections.length?raw.selections:[raw];
   for(const s of ss){if((s.date||'')<now||cancelled.has(`${s.date}|${s.courtId}`))continue;
    const number=Number((s.courtId||'').replace('court_',''));const start=mins(s.startTime||'00:00');
    if(number>data.courtCount || start<mins(data.openingTime) || start+60>mins(data.closingTime))return res.status(409).json({success:false,message:'Thay đổi này ảnh hưởng lịch đã xác nhận. Hãy xử lý các đơn liên quan trước.'});
   }
  }
  await ref.update({...data,updatedAt:FieldValue.serverTimestamp()});res.json({success:true});
 }catch(e){fail(res,e)}
});
module.exports=router;
