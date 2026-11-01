require('dotenv').config();
const express = require('express');
const cors = require('cors');
const {db} = require('./firebase');
const app=express();
app.use(cors());
app.use(express.json());

const refundSandboxRoutes=require('./refundSandboxRoutes');
app.use('/api',refundSandboxRoutes);
const bookingRoutes=require('./bookingRoutes');
app.use('/api',bookingRoutes);
const vnpayRoutes=require('./vnpayRoutes');
app.use('/api',vnpayRoutes);
const sepayRoutes=require('./sepayRoutes');
app.use('/api',sepayRoutes);
const locationRoutes=require('./locationRoutes');
app.use('/api',locationRoutes);
const membershipRoutes=require('./membershipRoutes');
app.use('/api',membershipRoutes);
const membershipBookingRoutes=require('./membershipBookingRoutes');
app.use('/api',membershipBookingRoutes);
const pushRoutes=require('./pushRoutes');
app.use('/api',pushRoutes);

app.get('/api/firebase-health',async(req,res)=>{
  try{
    await db.collection('fields').limit(1).get();
    res.json({success:true,message:'Firebase Firestore connected!'});
  }catch(error){
    console.error('Firebase error:',error);
    res.status(500).json({success:false,message:'Firebase connection failed'});
  }
});
const PORT=process.env.PORT||3000;
app.get('/api/health',(req,res)=>res.json({message:'Sports Booking API is running'}));
app.get('/api/fields',async(req,res)=>{
  try{
    const {sport,search}=req.query;
    const snapshot=await db.collection('fields').get();
    let result=snapshot.docs.map(doc=>({...doc.data(),id:doc.id}));
    if(typeof sport==='string'&&sport!=='Tất cả')
      result=result.filter(field=>typeof field.sport==='string'&&field.sport.toLowerCase()===sport.toLowerCase());
    if(typeof search==='string'&&search.trim()){
      const keyword=search.trim().toLowerCase();
      result=result.filter(field=>[field.name,field.address,field.sport].some(value=>typeof value==='string'&&value.toLowerCase().includes(keyword)));
    }
    res.status(200).json({success:true,count:result.length,fields:result});
  }catch(error){
    console.error('Error fetching fields:',error);
    res.status(500).json({success:false,message:'Không thể tải danh sách sân.'});
  }
});
app.get('/api/fields/:id',async(req,res)=>{
  try{
    const doc=await db.collection('fields').doc(req.params.id).get();
    if(!doc.exists)return res.status(404).json({success:false,message:'Không tìm thấy sân thể thao.'});
    res.status(200).json({success:true,field:{...doc.data(),id:doc.id}});
  }catch(error){
    console.error('Error fetching field:',error);
    res.status(500).json({success:false,message:'Không thể tải thông tin sân.'});
  }
});
if(require.main===module){
  app.listen(PORT,'0.0.0.0',()=>console.log(`API is running on port ${PORT}`));
}
module.exports=app;
