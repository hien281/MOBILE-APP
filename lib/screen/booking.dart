import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'fixed_booking.dart';

class BookingScreen extends StatefulWidget {
  final String fieldId;
  final String fieldName;
  final int price;
  final String baseUrl;
  final String accessToken;
  const BookingScreen({super.key, required this.fieldId, required this.fieldName, required this.price, required this.baseUrl, required this.accessToken});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const primary = Color(0xFF1E147B);
  final Set<String> _selected = {};
  final Map<String, Set<String>> _busy = {};
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  int _request = 0;
  static const courts = ['court_1', 'court_2', 'court_3'];
  static const hours = [6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21];
  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  String _time(int h) => '${h.toString().padLeft(2,'0')}:00';
  String _money(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  String _key(String court, String time) => '$court|$time';
  bool _past(int h) => !DateTime(_date.year,_date.month,_date.day,h).isAfter(DateTime.now());

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _request++; super.dispose(); }
  Future<void> _load() async {
    final id = ++_request;
    setState(() { _loading = true; _error = null; _selected.clear(); _busy.clear(); });
    try {
      final uri = Uri.parse('${widget.baseUrl}/fields/${Uri.encodeComponent(widget.fieldId)}/availability').replace(queryParameters: {'date': _dateKey(_date)});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['success'] != true) throw Exception(data is Map ? data['message'] : 'Lỗi dữ liệu');
      if (data['courts'] is! List) throw Exception('Backend chưa hỗ trợ 3 sân. Hãy deploy bookingRoutes.js mới.');
      for (final court in data['courts'] as List) {
        final courtId = court['courtId'].toString();
        _busy[courtId] = (court['slots'] as List).where((s) => s['available'] != true).map<String>((s) => s['startTime'].toString()).toSet();
      }
      if (!mounted || id != _request) return;
      setState(() {});
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }
  Future<void> _book() async {
    if (_selected.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Bạn cần đăng nhập lại.');
      final selections = _selected.map((key) { final parts = key.split('|'); return {'date': _dateKey(_date), 'courtId': parts[0], 'startTime': parts[1]}; }).toList();
      final response = await http.post(Uri.parse('${widget.baseUrl}/bookings'), headers: {'Content-Type':'application/json','Authorization':'Bearer $token'}, body: jsonEncode({'fieldId':widget.fieldId,'selections':selections})).timeout(const Duration(seconds: 30));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted) return;
      if (response.statusCode == 201 && data is Map && data['success'] == true) { Navigator.pop(context,true); return; }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data is Map ? (data['message']?.toString() ?? 'Đặt thất bại') : 'Đặt thất bại')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally { if (mounted) setState(() => _submitting = false); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(title: const Text('Đặt sân',style:TextStyle(fontWeight:FontWeight.bold)),centerTitle:true),
      body: Column(children: [
        Expanded(child: ListView(padding:const EdgeInsets.all(12),children:[
          Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(widget.fieldName,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Text('${_money(widget.price)}đ / giờ',style:const TextStyle(color:primary))]))),
          const SizedBox(height:12),
          Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
            Row(children:[IconButton(onPressed:_date.isAfter(DateUtils.dateOnly(DateTime.now())) ? () { setState(() => _date = _date.subtract(const Duration(days:1))); _load(); } : null,icon:const Icon(Icons.chevron_left)),Expanded(child:Center(child:Text('${_date.day}/${_date.month}/${_date.year}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)))),IconButton(onPressed:(){setState(()=>_date=_date.add(const Duration(days:1)));_load();},icon:const Icon(Icons.chevron_right))]),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Column(children:[Text(_error!,style:const TextStyle(color:Colors.red)),TextButton(onPressed:_load,child:const Text('Thử lại'))]),
            if (!_loading && _error == null) ...[
              Row(children:[const SizedBox(width:56,child:Text('Giờ')),for (var i=0;i<3;i++) Expanded(child:Center(child:Text('Sân ${i+1}',style:const TextStyle(fontWeight:FontWeight.bold))))]),
              for (final h in hours) SizedBox(height:67,child:Row(children:[SizedBox(width:56,child:Text(_time(h),style:const TextStyle(fontSize:12))),for (final court in courts) Expanded(child:Padding(padding:const EdgeInsets.all(3),child:Builder(builder:(context){
                final time=_time(h); final key=_key(court,time); final booked=_busy[court]?.contains(time)??false; final disabled=booked||_past(h); final selected=_selected.contains(key);
                return InkWell(onTap:disabled?null:()=>setState((){if(selected){_selected.remove(key);}else{_selected.add(key);}}),child:Container(alignment:Alignment.center,decoration:BoxDecoration(color:disabled?Colors.grey.shade200:selected?const Color(0xFFE5E0FF):const Color(0xFFF7F8FC),borderRadius:BorderRadius.circular(9),border:Border.all(color:selected?primary:Colors.grey.shade300,width:selected?2:1)),child:Text(booked?'Hết chỗ':_past(h)?'Đã qua':'${_money(widget.price)}đ',textAlign:TextAlign.center,style:TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:disabled?Colors.grey:primary))));
              }))) ])),
            ]
          ]))),
          const Padding(padding:EdgeInsets.all(8),child:Text('Chạm nhiều ô để chọn nhiều khung giờ hoặc nhiều sân.',style:TextStyle(color:Colors.grey,fontSize:12)))
        ])),
        Container(padding:const EdgeInsets.fromLTRB(16,12,16,12),color:Colors.white,child:SafeArea(top:false,child:Column(mainAxisSize:MainAxisSize.min,children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${_selected.length} khung giờ đã chọn',style:const TextStyle(fontWeight:FontWeight.bold)),Text('${_money(_selected.length*widget.price)}đ',style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:primary))]),
          const SizedBox(height:12),
          Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FixedBookingScreen(fieldId:widget.fieldId,fieldName:widget.fieldName,price:widget.price,baseUrl:widget.baseUrl))),child:const Text('Đặt cố định'))),const SizedBox(width:10),Expanded(child:FilledButton(style:FilledButton.styleFrom(backgroundColor:primary),onPressed:_selected.isNotEmpty&&!_submitting?_book:null,child:Text(_submitting?'Đang đặt...':'Tiếp tục')))])
        ])))
      ]),
    );
  }
}
