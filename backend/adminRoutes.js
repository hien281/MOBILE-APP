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

router.get('/admin/overview',async(req,res)=>{
 try{
  const [fs,bs,ms,mos]=await Promise.all(['fields','bookings','memberships','membership_orders'].map(c=>db.collection(c).get()));
  const names=Object.fromEntries(fs.docs.map(x=>[x.id,x.data().name||x.id]));
  const perDay={},perVenue={},perSport={},customers=new Set();
  let confirmed=0,sessions=0,paidRevenue=0;
  for(const doc of bs.docs){
   const d=doc.data(),fieldId=d.fieldId||'unknown',sport=fs.docs.find(f=>f.id===fieldId)?.data().sport||'Khác';
   if(d.userId)customers.add(d.userId);
   const selections=Array.isArray(d.selections)&&d.selections.length?d.selections:[d];
   if(d.status==='confirmed'){
    confirmed++;sessions+=selections.length;
    const row=perVenue[fieldId]??={id:fieldId,name:names[fieldId]||fieldId,bookings:0,revenue:0};
    row.bookings+=selections.length;
    perSport[sport]=(perSport[sport]||0)+selections.length;
    for(const slot of selections)if(/^\d{4}-\d{2}-\d{2}$/.test(slot.date||''))perDay[slot.date]=(perDay[slot.date]||0)+1;
   }
   if(d.paymentStatus==='paid'&&d.bookingType!=='membership'){
    const revenue=Number(d.totalPrice)||0;paidRevenue+=revenue;
    const row=perVenue[fieldId]??={id:fieldId,name:names[fieldId]||fieldId,bookings:0,revenue:0};row.revenue+=revenue;
   }
  }
  const mo=mos.docs.map(x=>({id:x.id,...x.data()}));
  const paidMemberships=mo.filter(x=>x.paymentStatus==='paid');
  const membershipRevenue=paidMemberships.reduce((n,x)=>n+(Number(x.totalPrice)||0),0);
  const venue=Object.values(perVenue);
  res.json({success:true,stats:{bookingCustomers:customers.size,orders:bs.size,confirmed,sessions,fields:fs.size,paidRevenue,membershipOrders:mo.length,membershipPaid:paidMemberships.length,membershipRevenue,membershipPackages:ms.size},
   chart:Object.entries(perDay).sort(([x],[y])=>x.localeCompare(y)).slice(-14).map(([date,count])=>({date,count})),
   topRevenue:[...venue].sort((x,y)=>y.revenue-x.revenue).slice(0,10),
   topBookings:[...venue].sort((x,y)=>y.bookings-x.bookings).slice(0,10),
   bySport:Object.entries(perSport).map(([name,count])=>({name,count})).sort((x,y)=>y.count-x.count)});
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
 const openingTime=clean(body.openingTime), closingTime=clean(body.closingTime);
 const price=Number(body.price), courtCount=Number(body.courtCount);
 const rating=body.rating===''||body.rating==null?0:Number(body.rating);
 const latitude=body.latitude===''||body.latitude==null?null:Number(body.latitude);
 const longitude=body.longitude===''||body.longitude==null?null:Number(body.longitude);
 const imageUrl=clean(body.imageUrl), phone=clean(body.phone), googleMapsUrl=clean(body.googleMapsUrl);
 const isPopular=body.isPopular===true||body.isPopular==='true';
 const isActive=body.isActive!==false&&body.isActive!=='false';
 const facilities=Array.isArray(body.facilities)?body.facilities.map(clean).filter(Boolean):[];
 const images=Array.isArray(body.images)?body.images.map(clean).filter(Boolean):[];
 const webURL=value=>{if(!value)return true;try{const u=new URL(value);return u.protocol==='https:'&&u.hostname.length>0;}catch(_){return false;}};
 if(!name||name.length>150||!address||address.length>350||!['Bóng đá','Cầu lông','Tennis','Pickleball'].includes(sport))return null;
 if(!timeOK(openingTime)||!timeOK(closingTime)||mins(openingTime)>=mins(closingTime))return null;
 if(!Number.isSafeInteger(price)||price<0||price>100000000||!Number.isInteger(courtCount)||courtCount<1||courtCount>100)return null;
 if(!Number.isFinite(rating)||rating<0||rating>5)return null;
 if(latitude!==null&&(!Number.isFinite(latitude)||latitude< -90||latitude>90))return null;
 if(longitude!==null&&(!Number.isFinite(longitude)||longitude< -180||longitude>180))return null;
 if(!webURL(imageUrl)||!webURL(googleMapsUrl)||images.length>12||images.some(x=>!webURL(x)))return null;
 if(imageUrl.length>1500||phone.length>40||googleMapsUrl.length>1500||facilities.length>30||facilities.some(x=>x.length>90))return null;
 return {name,address,sport,openingTime,closingTime,price,courtCount,rating,imageUrl,
   latitude,longitude,phone,googleMapsUrl,isPopular,isActive,facilities,images};
}
router.post('/admin/fields',async(req,res)=>{
 try {const data=validInput(req.body||{});if(!data)return res.status(400).json({success:false,message:'Thông tin sân chưa hợp lệ.'});
  const ref=await db.collection('fields').add({...data,createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});
  await audit(req,'create-field',ref.id);res.status(201).json({success:true,id:ref.id});
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
  await ref.update({...data,updatedAt:FieldValue.serverTimestamp()});await audit(req,'update-field',req.params.id);res.json({success:true});
 }catch(e){fail(res,e)}
});

const urlOk=v=>!v||(/^https:\/\//.test(v)&&v.length<=1800);
const safeId=id=>/^[a-zA-Z0-9_-]{1,150}$/.test(id);
function membershipData(x){
 const cardName=clean(x.cardName),venue=clean(x.venue),sport=clean(x.sport),fieldId=clean(x.fieldId);
 const price=Number(x.price),freeSlots=Number(x.freeSlots),months=Number(x.months);
 if(!cardName||cardName.length>160||!venue||venue.length>160||!Number.isSafeInteger(price)||price<=0||!Number.isInteger(freeSlots)||freeSlots<0||freeSlots>10000||!Number.isInteger(months)||months<1||months>24)return null;
 const d={cardName,venue,sport,fieldId,price,freeSlots,duration:months+' Tháng',isActive:x.isActive!==false,
  description:clean(x.description),benefits:clean(x.benefits),policy:clean(x.policy),applyTime:clean(x.applyTime),openSale:clean(x.openSale),address:clean(x.address),imageUrl:clean(x.imageUrl),logoUrl:clean(x.logoUrl)};
 if(!urlOk(d.imageUrl)||!urlOk(d.logoUrl)||[d.description,d.benefits,d.policy].some(v=>v.length>3500))return null;
 return d;
}
function eventData(x){
 const title=clean(x.title),content=clean(x.content??x.description),venue=clean(x.venue),imageUrl=clean(x.imageUrl);
 if(!title||title.length>170||content.length>6000||venue.length>200||!urlOk(imageUrl))return null;
 return {title,content,venue,imageUrl,address:clean(x.address),postTime:clean(x.postTime),tag:clean(x.tag),coming:clean(x.coming),isActive:x.isActive!==false};
}
router.get('/admin/memberships',async(req,res)=>{
 try{
  const [plans,orders]=await Promise.all([db.collection('memberships').get(),db.collection('membership_orders').get()]);
  const counts={};
  for(const d of orders.docs){const x=d.data(),id=x.membershipId;if(!id)continue;const s=counts[id]??={orders:0,paid:0,revenue:0};s.orders++;if(x.paymentStatus==='paid'){s.paid++;s.revenue+=Number(x.totalPrice)||0}}
  res.json({success:true,packages:plans.docs.map(d=>({...jsonDoc(d),sales:counts[d.id]||{orders:0,paid:0,revenue:0}})),recentOrders:orders.docs.map(jsonDoc).sort((a,b)=>String(b.createdAt||'').localeCompare(String(a.createdAt||''))).slice(0,100)});
 }catch(e){fail(res,e)}
});
router.post('/admin/memberships',async(req,res)=>{
 try{const d=membershipData(req.body||{});if(!d)return res.status(400).json({success:false,message:'Thông tin gói không hợp lệ.'});
 const ref=await db.collection('memberships').add({...d,createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});await audit(req,'create-membership',ref.id);res.status(201).json({success:true,id:ref.id});
 }catch(e){fail(res,e)}
});
router.put('/admin/memberships/:id',async(req,res)=>{
 try{if(!safeId(req.params.id))return res.status(400).json({success:false,message:'Mã không hợp lệ.'});
 const ref=db.collection('memberships').doc(req.params.id),snap=await ref.get();if(!snap.exists)return res.status(404).json({success:false,message:'Không tìm thấy gói.'});
 const d=membershipData(req.body||{});if(!d)return res.status(400).json({success:false,message:'Thông tin không hợp lệ.'});
 await ref.update({...d,updatedAt:FieldValue.serverTimestamp()});await audit(req,'update-membership',req.params.id);res.json({success:true});
 }catch(e){fail(res,e)}
});
router.get('/admin/events',async(req,res)=>{
 try{const snap=await db.collection('event').get();res.json({success:true,events:snap.docs.map(jsonDoc)});}catch(e){fail(res,e)}
});
router.post('/admin/events',async(req,res)=>{
 try{const d=eventData(req.body||{});if(!d)return res.status(400).json({success:false,message:'Nội dung chưa hợp lệ.'});
 const ref=await db.collection('event').add({...d,createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});await audit(req,'create-event',ref.id);res.status(201).json({success:true,id:ref.id});}catch(e){fail(res,e)}
});
router.put('/admin/events/:id',async(req,res)=>{
 try{if(!safeId(req.params.id))return res.status(400).json({success:false,message:'Mã không hợp lệ.'});
 const ref=db.collection('event').doc(req.params.id);if(!(await ref.get()).exists)return res.status(404).json({success:false,message:'Không tìm thấy tin.'});
 const d=eventData(req.body||{});if(!d)return res.status(400).json({success:false,message:'Thông tin chưa hợp lệ.'});
 await ref.update({...d,updatedAt:FieldValue.serverTimestamp()});await audit(req,'update-event',req.params.id);res.json({success:true});}catch(e){fail(res,e)}
});


const compactDoc=d=>({id:d.id,...d.data()});
const readCollection=async name=>(await db.collection(name).get()).docs.map(compactDoc);
const audit=async(req,action,target,detail={})=>{
 try{await db.collection('admin_audit_logs').add({actorUid:req.adminUid,action,target,detail,createdAt:FieldValue.serverTimestamp()});}catch(err){console.error('Audit log error:',err)}
};
router.get('/admin/customers',async(req,res)=>{
 try{
  const [users,bookings,orders,cards]=await Promise.all(['users','bookings','membership_orders','user_memberships'].map(readCollection));
  const byId=new Map();
  for(const u of users){const id=u.id;byId.set(id,{...u,uid:id,bookings:0,paidBooking:0,spent:0,membershipPurchases:0,activeCards:0})}
  for(const b of bookings){if(!b.userId)continue;const x=byId.get(b.userId)||{uid:b.userId,bookings:0,paidBooking:0,spent:0,membershipPurchases:0,activeCards:0};x.bookings++;if(b.paymentStatus==='paid'){x.paidBooking++;x.spent+=Number(b.totalPrice)||0}byId.set(b.userId,x)}
  for(const o of orders){if(!o.userId)continue;const x=byId.get(o.userId)||{uid:o.userId,bookings:0,paidBooking:0,spent:0,membershipPurchases:0,activeCards:0};if(o.paymentStatus==='paid'){x.membershipPurchases++;x.spent+=Number(o.totalPrice)||0}byId.set(o.userId,x)}
  for(const c of cards){const x=byId.get(c.userId);if(x && c.status==='active')x.activeCards++}
  res.json({success:true,customers:[...byId.values()].sort((x,y)=>y.spent-x.spent)});
 }catch(e){fail(res,e)}
});
router.get('/admin/calendar',async(req,res)=>{
 try{
  const date=clean(req.query.date),fieldId=clean(req.query.fieldId);
  if(!/^\d{4}-\d{2}-\d{2}$/.test(date))return res.status(400).json({success:false,message:'Ngày không hợp lệ.'});
  const [bookings,fields]=await Promise.all([readCollection('bookings'),readCollection('fields')]);
  const entries=[];
  for(const b of bookings){if(fieldId && b.fieldId!==fieldId)continue;
   const cancelled=new Set(b.cancelledSessions||[]);
   for(const s of (Array.isArray(b.selections)&&b.selections.length?b.selections:[b])){
    if(s.date!==date)continue;
    const key=s.date+'|'+(s.courtId||'court_1');
    if(cancelled.has(key)||['cancelled','expired'].includes(b.status))continue;
    entries.push({bookingId:b.id,fieldId:b.fieldId,courtId:s.courtId||'court_1',startTime:s.startTime,endTime:s.endTime,userId:b.userId,status:b.status,paymentStatus:b.paymentStatus});
   }
  }
  entries.sort((x,y)=>String(x.startTime).localeCompare(String(y.startTime)));
  res.json({success:true,fields:fields.map(x=>({id:x.id,name:x.name,courtCount:x.courtCount,openingTime:x.openingTime,closingTime:x.closingTime})),entries});
 }catch(e){fail(res,e)}
});
router.get('/admin/payments',async(req,res)=>{
 try{
  const [bookings,orders]=await Promise.all([readCollection('bookings'),readCollection('membership_orders')]);
  const rows=[...bookings.map(x=>({...x,kind:'booking'})),...orders.map(x=>({...x,kind:'membership'}))].sort((a,b)=>String(b.createdAt||'').localeCompare(String(a.createdAt||'')));
  const refunds=bookings.flatMap(x=>{
   const arr=[];
   if(x.refundRequestStatus||x.refundSandbox)arr.push({bookingId:x.id,userId:x.userId,amount:x.refundAmount,status:x.refundSandbox?.status||x.refundRequestStatus,sessionKey:'Toàn đơn',simulation:!!x.refundSandbox});
   for(const [key,v] of Object.entries(x.refundSessionRequests||{}))arr.push({bookingId:x.id,userId:x.userId,amount:v.amount,status:v.status,sessionKey:v.sessionKey||key,simulation:!!v.simulation});
   return arr;
  });
  res.json({success:true,transactions:rows.slice(0,500),refunds});
 }catch(e){fail(res,e)}
});
router.get('/admin/customer-memberships',async(req,res)=>{
 try{const cards=await readCollection('user_memberships');res.json({success:true,cards});}catch(e){fail(res,e)}
});
router.get('/admin/audit',async(req,res)=>{
 try{const snap=await db.collection('admin_audit_logs').orderBy('createdAt','desc').limit(150).get();res.json({success:true,logs:snap.docs.map(d=>({...compactDoc(d),createdAt:asDate(d.data().createdAt)}))});}catch(e){fail(res,e)}
});
router.get('/admin/admins',async(req,res)=>{
 try{
  const ids=(process.env.SPORTY_ADMIN_UIDS||'').split(',').map(s=>s.trim()).filter(Boolean);
  const admins=await Promise.all(ids.map(async uid=>{try{const u=await getAuth().getUser(uid);return {uid,email:u.email||'',displayName:u.displayName||''}}catch(_){return {uid,email:'Chưa tìm thấy trên Firebase Auth'}}}));
  res.json({success:true,admins,source:'SPORTY_ADMIN_UIDS',note:'Quyền Admin đang cấu hình tại Vercel Environment Variables. Tài khoản có custom claim admin cũng có thể truy cập.'});
 }catch(e){fail(res,e)}
});
router.get('/admin/reports',async(req,res)=>{
 try{
  const [bookings,orders]=await Promise.all([readCollection('bookings'),readCollection('membership_orders')]);
  const monthly={};
  const add=(date,kind,amount)=>{const m=String(date||'').slice(0,7);if(!/^\d{4}-\d{2}$/.test(m))return;const x=monthly[m]??={month:m,booking:0,membership:0};x[kind]+=Number(amount)||0};
  for(const b of bookings)if(b.paymentStatus==='paid'&&b.bookingType!=='membership')add(asDate(b.createdAt),'booking',b.totalPrice);
  for(const o of orders)if(o.paymentStatus==='paid')add(o.createdAt,'membership',o.totalPrice);
  res.json({success:true,monthly:Object.values(monthly).sort((a,b)=>a.month.localeCompare(b.month))});
 }catch(e){fail(res,e)}
});

module.exports=router;
