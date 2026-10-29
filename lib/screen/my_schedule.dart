import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';

class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});
  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}
class _MyScheduleScreenState extends State<MyScheduleScreen> {
  bool loading = true;
  String? error;
  List<dynamic> cards = [], bookings = [];
  @override void initState() {super.initState(); refresh();}
  Future<void> refresh() async {
    setState(() {loading=true;error=null;});
    try {
      final token=await FirebaseAuth.instance.currentUser?.getIdToken();
      if(token==null) throw Exception('Vui lòng đăng nhập.');
      Future<Map<String,dynamic>> get(String path) async {
        final r=await http.get(Uri.parse('${ApiClient.baseUrl}/$path'),headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:20));
        final v=jsonDecode(utf8.decode(r.bodyBytes));
        if(r.statusCode!=200 || v is! Map || v['success']!=true) throw Exception(v is Map ? v['message'] : 'Không thể tải dữ liệu');
        return Map<String,dynamic>.from(v);
      }
      final results=await Future.wait([get('my-memberships'),get('my-bookings')]);
      if(mounted) setState(() {cards=results[0]['memberships'] as List? ?? [];bookings=results[1]['bookings'] as List? ?? [];});
    } catch(e) {if(mounted) setState(()=>error=e.toString());}
    finally {if(mounted) setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFEFFF7),
    body: SafeArea(child: RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(18),children:[
      const Text('Lịch của tôi',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xFF35167F))),
      const SizedBox(height:16),
      const Text('Thẻ hội viên của tôi',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(loading) const LinearProgressIndicator(),
      if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
      if(!loading && cards.isEmpty) const Padding(padding:EdgeInsets.all(12),child:Text('Bạn chưa có thẻ hội viên.')),
      for(final raw in cards) if(raw is Map) Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${raw['membershipName'] ?? 'Thẻ hội viên'}',style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Text('Còn ${raw['remainingSlots'] ?? 0} / ${raw['totalSlots'] ?? 0} lượt'),
        Text('Hạn sử dụng: ${raw['expiresAt']?.toString().split('T').first ?? '-'}'),
        Text('Trạng thái: ${raw['status'] ?? '-'}'),
      ]))),
      const SizedBox(height:18),
      const Text('Các lịch đã đặt',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(!loading && bookings.isEmpty) const Padding(padding:EdgeInsets.all(12),child:Text('Chưa có lịch đặt sân.')),
      for(final raw in bookings) if(raw is Map) Card(child:ListTile(
        title:Text('Sân: ${raw['fieldId'] ?? '-'}'),
        subtitle:Text('${(raw['selections'] is List && (raw['selections'] as List).isNotEmpty) ? (raw['selections'] as List).map((s)=>'${s['date']} ${s['startTime']}–${s['endTime']} (${s['courtId']})').join(', ') : raw['date'] ?? '-'}\nTrạng thái: ${raw['status'] ?? '-'}'),
        isThreeLine:true,
        trailing:Chip(label:Text(raw['bookingType']=='membership'?'Hội viên':'Đặt thường',style:const TextStyle(fontSize:11))),
      )),
    ]))),
  );
}
