const express = require('express');
const { db } = require('./firebase');
const { requireAuth } = require('./authMiddleware');
const router = express.Router();

const dateOK = s => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s + 'T00:00:00Z')) && new Date(s + 'T00:00:00Z').toISOString().slice(0, 10) === s;
const slotKey = (f,c,d,t) => `${f}_${c}_${d}_${t.replace(':','-')}`;
const expiredHold = (s,now) => s.status === 'held' && Number.isFinite(Date.parse(s.expiresAt)) && Date.parse(s.expiresAt) <= now;

function parseClock(hour, minute, meridiem) {
  let h = Number(hour), m = Number(minute);
  if (!Number.isInteger(h) || !Number.isInteger(m) || m > 59) return null;
  if (meridiem) {
    if (h < 1 || h > 12) return null;
    h = (h % 12) + (meridiem.toUpperCase() === 'PM' ? 12 : 0);
  } else if (h > 23) return null;
  return h * 60 + m;
}

function allowedByPackage(packageData, date, times, field) {
  const rule = String(packageData.applyTime || '').trim();
  const lower = rule.toLowerCase();
  if (!rule) return false;
  const day = new Date(date + 'T00:00:00Z').getUTCDay();
  if (Array.isArray(packageData.allowedWeekdays) && packageData.allowedWeekdays.length > 0) {
    if (!packageData.allowedWeekdays.includes(day === 0 ? 7 : day)) return false;
  } else if (/thứ\\s*2\\s*[-–]\\s*thứ\\s*6/.test(lower) && (day === 0 || day === 6)) return false;
  else if (/thứ\\s*2\\s*[-–]\\s*thứ\\s*7/.test(lower) && day === 0) return false;
  else if (/thứ\\s*2\\s*,\\s*thứ\\s*4\\s*,\\s*thứ\\s*6/.test(lower) && ![1,3,5].includes(day)) return false;
  if (lower === 'không giới hạn') return true; // Still subject to venue hours and remaining uses.
  // A fixed schedule requires explicit structured hours; never guess from the label.
  if (lower === 'khung giờ cố định') {
    if (!Array.isArray(packageData.fixedTimeSlots) || packageData.fixedTimeSlots.length === 0) return false;
    return times.every(t => packageData.fixedTimeSlots.includes(t));
  }
  const window = rule.match(/(\d{1,2}):(\d{2})\s*(AM|PM)?\s*[-–]\s*(\d{1,2}):(\d{2})\s*(AM|PM)?/i);
  if (!window) return false;
  const start = parseClock(window[1], window[2], window[3]);
  const end = parseClock(window[4], window[5], window[6]);
  if (start === null || end === null || end <= start) return false;
  if (Array.isArray(packageData.fixedTimeSlots) && packageData.fixedTimeSlots.length && !times.every(t=>packageData.fixedTimeSlots.includes(t))) return false;
  return times.every(t => {
    const m = Number(t.slice(0,2)) * 60;
    return m >= start && m + 60 <= end;
  });
}

router.get('/my-memberships', requireAuth, async (req,res) => {
  try {
    const snap = await db.collection('user_memberships').where('userId','==',req.user.id).get();
    const memberships = snap.docs.map(d => ({id:d.id,...d.data()}));
    return res.json({success:true,memberships});
  } catch(e) { console.error(e); return res.status(500).json({success:false,message:'Không tải được thẻ hội viên.'}); }
});

router.get('/my-bookings', requireAuth, async (req,res) => {
  try {
    const snap = await db.collection('bookings').where('userId','==',req.user.id).get();
    const bookings = snap.docs.map(d=>({id:d.id,...d.data()})).sort((a,b)=>String(b.createdAt||'').localeCompare(String(a.createdAt||'')));
    return res.json({success:true,bookings});
  } catch(e) { console.error(e); return res.status(500).json({success:false,message:'Không tải được lịch đặt sân.'}); }
});

router.post('/membership-bookings', requireAuth, async (req,res) => {
  try {
    const {membershipCardId,fieldId,selections} = req.body || {};
    if (typeof membershipCardId !== 'string' || !/^[\w-]{1,128}$/.test(membershipCardId) ||
        typeof fieldId !== 'string' || !/^[\w-]{1,128}$/.test(fieldId) ||
        !Array.isArray(selections) || selections.length < 1 || selections.length > 3) {
      return res.status(400).json({success:false,message:'Chọn 1 đến 3 giờ liên tiếp trên cùng một sân.'});
    }
    const [first] = selections;
    if (!first || !dateOK(first.date) || !/^court_[1-9]\d*$/.test(first.courtId)) return res.status(400).json({success:false,message:'Ngày hoặc sân không hợp lệ.'});
    const times = selections.map(s=>s.startTime);
    if (selections.some(s=>s.date !== first.date || s.courtId !== first.courtId || !/^([01]\d|2[0-3]):00$/.test(s.startTime)) || new Set(times).size !== times.length) return res.status(400).json({success:false,message:'Các giờ phải thuộc cùng ngày và sân.'});
    times.sort();
    if (times.some((t,i)=>i && Number(t.slice(0,2)) !== Number(times[i-1].slice(0,2))+1)) return res.status(400).json({success:false,message:'Chỉ được chọn giờ liên tiếp.'});
    const now = Date.now();
    const nowVN = new Date(now+7*3600000).toISOString().slice(0,16);
    if (first.date+'T'+times[0] <= nowVN) return res.status(400).json({success:false,message:'Không thể đặt giờ đã qua.'});
    const cardRef=db.collection('user_memberships').doc(membershipCardId);
    const fieldRef=db.collection('fields').doc(fieldId);
    const bookingRef=db.collection('bookings').doc();
    const slotRefs=times.map(t=>db.collection('booking_slots').doc(slotKey(fieldId,first.courtId,first.date,t)));
    const legacyRefs=times.map(t=>db.collection('booking_slots').doc(`${fieldId}_${first.date}_${t.replace(':','-')}`));
    const result=await db.runTransaction(async tx=>{
      const [cardDoc,fieldDoc]=await Promise.all([tx.get(cardRef),tx.get(fieldRef)]);
      if (!cardDoc.exists || cardDoc.data().userId !== req.user.id) return {code:404,message:'Không tìm thấy thẻ hội viên.'};
      if (!fieldDoc.exists) return {code:404,message:'Không tìm thấy sân.'};
      const card=cardDoc.data(), field=fieldDoc.data();
      if (card.status !== 'active' || !Number.isSafeInteger(card.remainingSlots) || card.remainingSlots < 1) return {code:409,message:'Thẻ đã hết lượt hoặc không hoạt động.'};
      const startMs=Date.parse(first.date+'T'+times[0]+':00+07:00');
      const endMs=startMs+times.length*3600000;
      if (!Number.isFinite(Date.parse(card.activatedAt)) || !Number.isFinite(Date.parse(card.expiresAt)) || startMs < Date.parse(card.activatedAt) || endMs > Date.parse(card.expiresAt)) return {code:409,message:'Ngày đặt nằm ngoài thời hạn hội viên.'};
      if (!card.fieldId || card.fieldId !== fieldId) return {code:403,message:'Thẻ không áp dụng cho sân này.'};
      const packageDoc=await tx.get(db.collection('memberships').doc(card.membershipId));
      if (!packageDoc.exists || !allowedByPackage(packageDoc.data(),first.date,times,field)) return {code:403,message:'Khung giờ không thuộc quyền lợi gói hội viên.'};
      const rules=packageDoc.data();
      const maxHours=Number(rules.maxHoursPerBooking || (card.membershipId==='mem_06'?2:3));
      if (!Number.isInteger(maxHours) || maxHours<1 || times.length>maxHours) return {code:403,message:'Vượt số giờ tối đa của gói.'};
      const maxDaily=Number(rules.maxBookingsPerDay || 0);
      if (maxDaily>0) {
        const existing=await tx.get(db.collection('bookings').where('userId','==',req.user.id));
        const daily=existing.docs.filter(d=>{const b=d.data();return b.bookingType==='membership' && b.membershipCardId===membershipCardId && b.status==='confirmed' && Array.isArray(b.selections) && b.selections.some(s=>s.date===first.date);}).length;
        if(daily>=maxDaily) return {code:409,message:'Đã đạt số lượt đặt tối đa trong ngày.'};
      }
      const courtCount=Number(field.courtCount)||1;
      if (Number(first.courtId.slice(6))>courtCount) return {code:400,message:'Sân con không hợp lệ.'};
      const open=String(field.openingTime||'06:00'), close=String(field.closingTime||'22:00');
      if (times.some(t=>t<open || (Number(t.slice(0,2))+1)*60 > Number(close.slice(0,2))*60+Number(close.slice(3,5)))) return {code:400,message:'Ngoài giờ hoạt động.'};
      const [slotDocs,legacyDocs]=await Promise.all([Promise.all(slotRefs.map(r=>tx.get(r))),Promise.all(legacyRefs.map(r=>tx.get(r)))]);
      if (legacyDocs.some(d=>d.exists)) return {code:409,message:'Khung giờ đã có lịch đặt.'};
      const owners=new Map();
      for(const d of slotDocs) if(d.exists) {
        const s=d.data();
        if(!expiredHold(s,now) || !s.bookingId) return {code:409,message:'Khung giờ đã được đặt.'};
        owners.set(s.bookingId,db.collection('bookings').doc(s.bookingId));
      }
      const ownerDocs=await Promise.all([...owners.values()].map(r=>tx.get(r)));
      if(ownerDocs.some(d=>!d.exists || d.data().status!=='pending_payment' || Date.parse(d.data().expiresAt)>now)) return {code:409,message:'Khung giờ đang được thanh toán.'};
      ownerDocs.forEach(d=>tx.update(d.ref,{status:'expired',paymentStatus:'expired'}));
      const createdAt=new Date(now).toISOString();
      const booking={fieldId,userId:req.user.id,bookingType:'membership',membershipCardId,membershipId:card.membershipId,selections:times.map(t=>({date:first.date,courtId:first.courtId,startTime:t,endTime:String(Number(t.slice(0,2))+1).padStart(2,'0')+':00'})),totalPrice:0,status:'confirmed',paymentStatus:'paid',createdAt,confirmedAt:createdAt};
      tx.create(bookingRef,booking);
      slotRefs.forEach((r,i)=>tx.set(r,{bookingId:bookingRef.id,fieldId,date:first.date,courtId:first.courtId,startTime:times[i],status:'booked'}));
      tx.update(cardRef,{remainingSlots:card.remainingSlots-1});
      return {success:true,bookingId:bookingRef.id,remainingSlots:card.remainingSlots-1,booking};
    });
    if(result.code) return res.status(result.code).json({success:false,message:result.message});
    return res.status(201).json(result);
  } catch(e) {console.error('Membership booking:',e);return res.status(500).json({success:false,message:'Không thể đặt sân bằng thẻ.'});}
});


router.post('/membership-fixed-bookings', requireAuth, async (req,res) => {
  try {
    const {membershipCardId,fieldId,selections}=req.body||{};
    if(typeof membershipCardId!=='string'|| !/^[\\w-]{1,128}$/.test(membershipCardId) ||
       typeof fieldId!=='string'|| !/^[\\w-]{1,128}$/.test(fieldId) ||
       !Array.isArray(selections)||selections.length<1||selections.length>100)
      return res.status(400).json({success:false,message:'Lịch cố định không hợp lệ (tối đa 100 khung giờ).'});
    const groups=new Map(), unique=new Set();
    for(const s of selections){
      if(!s||!dateOK(s.date)||!/^court_[1-9]\\d*$/.test(s.courtId)||!/^([01]\\d|2[0-3]):00$/.test(s.startTime))
        return res.status(400).json({success:false,message:'Ngày, sân hoặc giờ không hợp lệ.'});
      const key=s.date+'|'+s.courtId,slot=key+'|'+s.startTime;
      if(unique.has(slot)) return res.status(400).json({success:false,message:'Có khung giờ trùng nhau.'});
      unique.add(slot);
      if(!groups.has(key))groups.set(key,{date:s.date,courtId:s.courtId,times:[]});
      groups.get(key).times.push(s.startTime);
    }
    if(groups.size>30)return res.status(400).json({success:false,message:'Tối đa 30 buổi mỗi lần đặt.'});
    const now=Date.now(), nowVN=new Date(now+7*3600000).toISOString().slice(0,16);
    for(const g of groups.values()){
      g.times.sort();
      if(g.date+'T'+g.times[0]<=nowVN || g.times.some((t,i)=>i&&Number(t.slice(0,2))!==Number(g.times[i-1].slice(0,2))+1))
        return res.status(400).json({success:false,message:'Các giờ trong mỗi buổi phải liên tiếp và ở tương lai.'});
    }
    const cardRef=db.collection('user_memberships').doc(membershipCardId);
    const fieldRef=db.collection('fields').doc(fieldId);
    const bookingRef=db.collection('bookings').doc();
    const slotRefs=selections.map(s=>db.collection('booking_slots').doc(slotKey(fieldId,s.courtId,s.date,s.startTime)));
    const legacyRefs=selections.map(s=>db.collection('booking_slots').doc(fieldId+'_'+s.date+'_'+s.startTime.replace(':','-')));
    const result=await db.runTransaction(async tx=>{
      // Firestore requires all reads to finish before the first write.
      const cardDoc=await tx.get(cardRef),fieldDoc=await tx.get(fieldRef);
      if(!cardDoc.exists||cardDoc.data().userId!==req.user.id)return {code:404,message:'Không tìm thấy thẻ hội viên.'};
      if(!fieldDoc.exists)return {code:404,message:'Không tìm thấy sân.'};
      const card=cardDoc.data(),field=fieldDoc.data();
      if(card.status!=='active'||!Number.isSafeInteger(card.remainingSlots)||card.remainingSlots<groups.size)
        return {code:409,message:'Thẻ không hoạt động hoặc không đủ lượt cho toàn bộ lịch.'};
      if(card.fieldId!==fieldId)return {code:403,message:'Thẻ không áp dụng cho sân này.'};
      const packageDoc=await tx.get(db.collection('memberships').doc(card.membershipId));
      if(!packageDoc.exists)return {code:404,message:'Không tìm thấy gói hội viên.'};
      const rules=packageDoc.data(),maxHours=Number(rules.maxHoursPerBooking||(card.membershipId==='mem_06'?2:3)),maxDaily=Number(rules.maxBookingsPerDay||0);
      if(!Number.isInteger(maxHours)||maxHours<1)return {code:403,message:'Giới hạn giờ của gói không hợp lệ.'};
      const startCard=Date.parse(card.activatedAt),endCard=Date.parse(card.expiresAt);
      if(!Number.isFinite(startCard)||!Number.isFinite(endCard))return {code:409,message:'Thời hạn thẻ không hợp lệ.'};
      const courtCount=Number(field.courtCount)||1,open=String(field.openingTime||'06:00'),close=String(field.closingTime||'22:00');
      const openMin=Number(open.slice(0,2))*60+Number(open.slice(3,5)),closeMin=Number(close.slice(0,2))*60+Number(close.slice(3,5));
      const dailyCounts=new Map();
      for(const g of groups.values()){
        const start=Date.parse(g.date+'T'+g.times[0]+':00+07:00'),end=start+g.times.length*3600000;
        if(start<startCard||end>endCard)return {code:409,message:'Có buổi nằm ngoài thời hạn thẻ.'};
        if(Number(g.courtId.slice(6))>courtCount)return {code:400,message:'Sân con không hợp lệ.'};
        if(g.times.length>maxHours||!allowedByPackage(rules,g.date,g.times,field))
          return {code:403,message:'Có buổi ngoài ngày/giờ hoặc vượt quyền lợi hội viên.'};
        if(g.times.some(t=>Number(t.slice(0,2))*60<openMin||(Number(t.slice(0,2))+1)*60>closeMin))
          return {code:403,message:'Có buổi ngoài giờ mở cửa.'};
        dailyCounts.set(g.date,(dailyCounts.get(g.date)||0)+1);
      }
      if(maxDaily>0&&[...dailyCounts.values()].some(n=>n>maxDaily))
        return {code:409,message:'Vượt số buổi tối đa trong ngày.'};
      if(maxDaily>0){
        const existing=await tx.get(db.collection('bookings').where('userId','==',req.user.id));
        for(const d of existing.docs){
          const b=d.data();
          if(b.bookingType!=='membership'||b.membershipCardId!==membershipCardId||b.status!=='confirmed')continue;
          const dates=new Set((b.selections||[]).map(s=>s.date));
          for(const date of dates)if(dailyCounts.has(date))dailyCounts.set(date,dailyCounts.get(date)+1);
        }
        if([...dailyCounts.values()].some(n=>n>maxDaily))return {code:409,message:'Đã có lịch hội viên trong một ngày được chọn.'};
      }
      const slotDocs=await Promise.all(slotRefs.map(r=>tx.get(r)));
      const legacyDocs=await Promise.all(legacyRefs.map(r=>tx.get(r)));
      if(legacyDocs.some(d=>d.exists))return {code:409,message:'Có giờ đã được đặt. Toàn bộ lịch chưa được tạo.'};
      const owners=new Map();
      for(const d of slotDocs)if(d.exists){
        const s=d.data();
        if(!expiredHold(s,now)||!s.bookingId)return {code:409,message:'Có giờ đã được đặt. Toàn bộ lịch chưa được tạo.'};
        owners.set(s.bookingId,db.collection('bookings').doc(s.bookingId));
      }
      const ownerDocs=await Promise.all([...owners.values()].map(r=>tx.get(r)));
      if(ownerDocs.some(d=>!d.exists||d.data().status!=='pending_payment'||Date.parse(d.data().expiresAt)>now))
        return {code:409,message:'Có giờ đang được giữ chỗ. Toàn bộ lịch chưa được tạo.'};
      const createdAt=new Date(now).toISOString();
      const normalized=selections.map(s=>({...s,endTime:String(Number(s.startTime.slice(0,2))+1).padStart(2,'0')+':00'}))
        .sort((a,b)=>a.date.localeCompare(b.date)||a.courtId.localeCompare(b.courtId)||a.startTime.localeCompare(b.startTime));
      ownerDocs.forEach(d=>tx.update(d.ref,{status:'expired',paymentStatus:'expired'}));
      tx.create(bookingRef,{fieldId,userId:req.user.id,bookingType:'membership',membershipCardId,membershipId:card.membershipId,
        selections:normalized,totalPrice:0,status:'confirmed',paymentStatus:'paid',createdAt,confirmedAt:createdAt,
        fixedSchedule:true,membershipUses:groups.size});
      selections.forEach((s,i)=>tx.set(slotRefs[i],{bookingId:bookingRef.id,fieldId,date:s.date,courtId:s.courtId,startTime:s.startTime,status:'booked'}));
      tx.update(cardRef,{remainingSlots:card.remainingSlots-groups.size});
      return {success:true,bookingId:bookingRef.id,remainingSlots:card.remainingSlots-groups.size,usedSlots:groups.size};
    });
    if(result.code)return res.status(result.code).json({success:false,message:result.message});
    return res.status(201).json(result);
  }catch(e){console.error('Fixed membership booking:',e);return res.status(500).json({success:false,message:'Không thể đặt cố định bằng thẻ.'});}
});

router.post('/membership-bookings/:id/cancel', requireAuth, async (req,res) => {
  try {
    const bookingRef=db.collection('bookings').doc(req.params.id);
    const result=await db.runTransaction(async tx=>{
      const doc=await tx.get(bookingRef);
      if(!doc.exists) return {code:404,message:'Không tìm thấy lịch đặt.'};
      const b=doc.data();
      if(b.userId!==req.user.id) return {code:403,message:'Bạn không có quyền huỷ lịch này.'};
      if(b.bookingType!=='membership') return {code:400,message:'Đây không phải lịch hội viên.'};
      if(b.status==='cancelled') return {success:true};
      if(b.status!=='confirmed') return {code:409,message:'Lịch không thể huỷ.'};
      const selections=Array.isArray(b.selections)?b.selections:[];
      if(!selections.length || !b.membershipCardId) return {code:409,message:'Thiếu thông tin lịch.'};
      const first=selections.map(s=>Date.parse(s.date+'T'+s.startTime+':00+07:00'));
      if(first.some(t=>!Number.isFinite(t)) || Math.min(...first)<=Date.now()) return {code:409,message:'Không thể huỷ lịch đã bắt đầu.'};
      const cardRef=db.collection('user_memberships').doc(b.membershipCardId);
      const card=await tx.get(cardRef);
      if(!card.exists || card.data().userId!==req.user.id) return {code:409,message:'Không tìm thấy thẻ hội viên.'};
      const refs=selections.map(s=>db.collection('booking_slots').doc(slotKey(b.fieldId,s.courtId,s.date,s.startTime)));
      const slots=await Promise.all(refs.map(r=>tx.get(r)));
      if(slots.some(s=>!s.exists || s.data().bookingId!==doc.id)) return {code:409,message:'Lịch sân đã thay đổi, vui lòng thử lại.'};
      tx.update(bookingRef,{status:'cancelled',cancelledAt:new Date().toISOString()});
      slots.forEach(s=>tx.delete(s.ref));
      const remaining=Number(card.data().remainingSlots)||0;
      const total=Number(card.data().totalSlots)||0;
      // A fixed booking consumes one use per scheduled session.
      const restored = Number.isSafeInteger(b.membershipUses) && b.membershipUses > 0 ? b.membershipUses : 1;
      tx.update(cardRef,{remainingSlots:Math.min(total,remaining+restored)});
      return {success:true,remainingSlots:Math.min(total,remaining+restored)};
    });
    if(result.code) return res.status(result.code).json({success:false,message:result.message});
    return res.json(result);
  } catch(e) {console.error('Cancel membership booking:',e);return res.status(500).json({success:false,message:'Không thể huỷ lịch hội viên.'});}
});

module.exports=router;
