import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import 'payment_screen.dart';

const _purple = Color(0xFF35167F);
const _background = Color(0xFFFEFFF7);

class MyScheduleScreen extends StatefulWidget {
  final bool isActive;
  const MyScheduleScreen({super.key, this.isActive = true});
  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  Timer? _timer;
  Timer? _countdownTimer;
  bool loading = true, busy = false;
  String? error;
  List<Map<String,dynamic>> bookings = [];
  Map<String,String> fieldNames = {};
  Map<String,String> fieldImages = {};
  int tab = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _countdownTimer = Timer.periodic(const Duration(seconds: 15), (_) { if (mounted && widget.isActive) setState(() {}); });
    refresh();
  }

  @override
  void didUpdateWidget(covariant MyScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _startTimer();
      if (widget.isActive) refresh(silent:true);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.isActive) {
      _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh(silent:true));
    }
  }

  @override
  void dispose() { _timer?.cancel(); _countdownTimer?.cancel(); super.dispose(); }

  Future<String> _token() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw Exception('Vui lòng đăng nhập.');
    return token;
  }

  Future<void> refresh({bool silent=false}) async {
    if (busy || !mounted) return;
    busy=true;
    if (!silent) setState(() {loading=true;error=null;});
    try {
      final token=await _token();
      final uri=Uri.parse('${ApiClient.baseUrl}/my-bookings').replace(queryParameters:{'_fresh':DateTime.now().millisecondsSinceEpoch.toString()});
      final r=await http.get(uri,headers:{'Authorization':'Bearer $token','Cache-Control':'no-cache'}).timeout(const Duration(seconds:18));
      final data=jsonDecode(utf8.decode(r.bodyBytes));
      if(r.statusCode!=200 || data is! Map || data['success']!=true) throw Exception(data is Map ? data['message']?.toString() ?? 'Không tải được lịch.' : 'Không tải được lịch.');
      final list=(data['bookings'] as List? ?? []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {bookings=list;error=null;});
      final ids=list.map((b)=>b['fieldId']?.toString()??'').where((id)=>id.isNotEmpty && !fieldNames.containsKey(id)).toSet();
      if (ids.isNotEmpty) {
        final entries=await Future.wait(ids.map((id) async {
          try {
            final response=await http.get(Uri.parse('${ApiClient.baseUrl}/fields/${Uri.encodeComponent(id)}')).timeout(const Duration(seconds:8));
            final d=jsonDecode(utf8.decode(response.bodyBytes));
            if(response.statusCode==200 && d is Map && d['field'] is Map) {
              final field=d['field'] as Map;
              final img=(field['imageUrl']??(field['images'] is List && (field['images'] as List).isNotEmpty?(field['images'] as List).first:null))?.toString();
              if(img!=null && img.startsWith('http')) fieldImages[id]=img;
              return MapEntry(id,(field['name']??id).toString());
            }
          } catch (_) {}
          return MapEntry(id,id);
        }));
        if(mounted) setState(()=>fieldNames.addEntries(entries));
      }
    } catch(e) {
      if(mounted) setState(()=>error=e.toString().replaceFirst('Exception: ',''));
    } finally {
      busy=false;
      if(mounted) setState(()=>loading=false);
    }
  }

  List<Map<String,dynamic>> _selections(Map<String,dynamic> b) {
    final raw=b['selections'];
    if(raw is List && raw.isNotEmpty) return raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(b['date']!=null) return [b];
    return [];
  }

  // Expand one parent order into session cards; keep the original order ID.
  List<Map<String,dynamic>> _sessions(Map<String,dynamic> booking) {
    final all = _selections(booking);
    if (all.isEmpty) return [booking];
    final groups = <String,List<Map<String,dynamic>>>{};
    for (final slot in all) {
      final key = "${slot['date']}|${slot['courtId']}";
      groups.putIfAbsent(key, () => []).add(slot);
    }
    if (groups.length == 1) return [booking];
    final cancelled = (booking['cancelledSessions'] as List? ?? []).map((e) => e.toString()).toSet();
    return groups.entries.map((e) {
      final item = Map<String,dynamic>.from(booking);
      item['selections'] = e.value;
      item['sessionKey'] = e.key;
      item['sessionCount'] = groups.length;
      if (cancelled.contains(e.key)) item['status'] = 'cancelled';
      return item;
    }).toList();
  }

  DateTime? _start(Map<String,dynamic> b) {
    final values=_selections(b).map((s)=>DateTime.tryParse("${s['date']}T${s['startTime']}:00+07:00")).whereType<DateTime>().toList();
    if(values.isEmpty) return null;
    values.sort();
    return values.first;
  }

  DateTime? _end(Map<String,dynamic> b) {
    final values=_selections(b).map((s)=>DateTime.tryParse("${s['date']}T${s['endTime'] ?? '00:00'}:00+07:00")).whereType<DateTime>().toList();
    if(values.isEmpty) return null;
    values.sort();
    return values.last;
  }

  bool _expiredPayment(Map<String,dynamic> b) => b['status']=='expired' || (b['status']=='pending_payment' && _remaining(b)==Duration.zero);
  bool _cancelled(Map<String,dynamic> b) => ['cancelled','canceled'].contains(b['status']) || _expiredPayment(b);
  bool _past(Map<String,dynamic> b) => !_cancelled(b) && (_end(b)?.isBefore(DateTime.now())??false);
  bool _upcoming(Map<String,dynamic> b) {
    final end=_end(b);
    return !_cancelled(b) && end!=null && end.isAfter(DateTime.now());
  }

  String _status(Map<String,dynamic> b) {
    final status=b['status']?.toString()??'';
    if(_expiredPayment(b)) return 'Hết hạn thanh toán';
    if(_cancelled(b)) return 'Đã huỷ';
    if(status=='pending_payment') return _remaining(b)>Duration.zero?'Chờ thanh toán':'Hết thời gian thanh toán';
    if(status=='confirmed' || status=='booked') return _upcoming(b)?'Đã xác nhận':'Đã hoàn thành';
    return status;
  }

  bool _canCancel(Map<String,dynamic> b) {
    final start=_start(b);
    if(start==null || !start.isAfter(DateTime.now())) return false;
    if(b['bookingType']=='membership') return b['status']=='confirmed';
    return _canPay(b);
  }


  Duration _remaining(Map<String,dynamic> b) {
    final expiry=DateTime.tryParse(b['expiresAt']?.toString()??'');
    if(expiry==null) return Duration.zero;
    final left=expiry.difference(DateTime.now());
    return left.isNegative?Duration.zero:left;
  }

  bool _pending(Map<String,dynamic> b) => b['status']=='pending_payment' && b['paymentStatus']=='pending';
  bool _canPay(Map<String,dynamic> b) => _pending(b) && _remaining(b)>Duration.zero;
  String _minutesLabel(Map<String,dynamic> b) => 'Còn ${(_remaining(b).inSeconds+59)~/60} phút để thanh toán';
  Future<void> _resumePayment(Map<String,dynamic> b) async {
    if(!_canPay(b)) return;
    final selections=_selections(b).map((s)=>s.map((k,v)=>MapEntry(k,v?.toString()??''))).toList();
    final expiry=DateTime.tryParse(b['expiresAt']?.toString()??'');
    if(expiry==null || selections.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PaymentScreen(
      bookingId:b['id'].toString(),
      fieldName:fieldNames[b['fieldId']]??b['fieldId']?.toString()??'Sân',
      totalPrice:(num.tryParse(b['totalPrice'].toString())??0).round(),
      expiresAt:expiry,
      baseUrl:ApiClient.baseUrl,
      selections:selections,
    )));
    if(mounted) refresh(silent:true);
  }

  Future<void> _cancel(Map<String,dynamic> b) async {
    final membership=b['bookingType']=='membership';
    final sessionKey=b['sessionKey']?.toString();
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Xác nhận huỷ lịch'),
      content:Text(membership?'Huỷ buổi này sẽ hoàn lại 1 lượt nếu còn ít nhất 24 giờ trước giờ chơi.':'Huỷ đơn đang chờ thanh toán và giải phóng khung giờ?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Giữ lịch')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Huỷ lịch'))],
    ));
    if(confirmed!=true || !mounted) return;
    try {
      final token=await _token();
      final id=b['id'].toString();
      final path=membership?'membership-bookings':'bookings';
      final endpoint=membership && sessionKey!=null ? '$path/${Uri.encodeComponent(b['id'].toString())}/cancel-session' : '$path/${Uri.encodeComponent(b['id'].toString())}/cancel';
      final r=await http.post(Uri.parse('${ApiClient.baseUrl}/$path/${Uri.encodeComponent(id)}/cancel'),headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:20));
      final data=jsonDecode(utf8.decode(r.bodyBytes));
      if(r.statusCode!=200 || data is! Map || data['success']!=true) throw Exception(data is Map ? data['message']?.toString()??'Không thể huỷ lịch.' : 'Không thể huỷ lịch.');
      await refresh(silent:true);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đã huỷ lịch thành công.')));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));
    }
  }

  void _details(Map<String,dynamic> b) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _BookingDetailPage(
        booking: b,
        venueName: fieldNames[b['fieldId']] ?? b['fieldId']?.toString() ?? 'Sân',
        imageUrl: fieldImages[b['fieldId']],
        selections: _selections(b),
        statusLabel: _status(b),
        canPay: _canPay(b),
        canCancel: _canCancel(b),
        remainingLabel: _pending(b) ? (_canPay(b) ? _minutesLabel(b) : 'Đã hết 10 phút giữ chỗ') : null,
        onPay: () => _resumePayment(b),
        onCancel: () => _cancel(b),
        onRefundRequest: () => _requestRefund(b),
      ),
    )).then((_) { if (mounted) refresh(silent:true); });
  }

  Future<void> _requestRefund(Map<String,dynamic> b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yêu cầu huỷ và hoàn tiền'),
        content: const Text('Nếu gửi yêu cầu trước giờ bắt đầu ít nhất 24 tiếng, bạn đủ điều kiện được hoàn 100% số tiền đã thanh toán. Yêu cầu sẽ chờ xử lý; sân chưa bị huỷ và tiền chưa được hoàn ngay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Để sau')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gửi yêu cầu')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final token = await _token();
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/bookings/${Uri.encodeComponent(b['id'].toString())}/refund-request'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['success'] != true) {
        throw Exception(data is Map ? data['message']?.toString() ?? 'Không gửi được yêu cầu.' : 'Không gửi được yêu cầu.');
      }
      await refresh(silent: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi yêu cầu. Lịch vẫn giữ nguyên cho đến khi được xử lý.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Widget _bookingCard(Map<String,dynamic> b) {
    final id=b['fieldId']?.toString()??'';
    final image=fieldImages[id];
    final member=b['bookingType']=='membership';
    final selections=_selections(b);
    final first=selections.isNotEmpty?selections.first:b;
    final status=_status(b);
    final cancelled=_cancelled(b);
    return Container(
      margin:const EdgeInsets.only(bottom:14),
      decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE8E3F1)),boxShadow:[BoxShadow(color:_purple.withValues(alpha:0.06),blurRadius:16,offset:const Offset(0,5))]),
      child:InkWell(borderRadius:BorderRadius.circular(20),onTap:()=>_details(b),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          ClipRRect(borderRadius:BorderRadius.circular(13),child:SizedBox(width:92,height:92,child:image==null?Container(color:const Color(0xFFF1EBFA),child:const Icon(Icons.sports_tennis,color:_purple,size:34)):Image.network(image,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFFF1EBFA),child:const Icon(Icons.sports_tennis,color:_purple))))),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(fieldNames[id]??id,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:_purple,fontSize:16,fontWeight:FontWeight.w800)),
            const SizedBox(height:6),
            Text('${first['date']??'-'} • ${first['startTime']??'-'}–${first['endTime']??'-'}',style:const TextStyle(fontSize:12,color:Colors.black87)),
            const SizedBox(height:5),
            Text('Sân ${(first['courtId']??'1').toString().replaceFirst('court_','')}${selections.length>1?' • ${selections.length} khung giờ':''}',style:const TextStyle(fontSize:12,color:Colors.black54)),
            const SizedBox(height:7),
            Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),decoration:BoxDecoration(color:member?const Color(0xFFEDE8FF):const Color(0xFFF3F4F6),borderRadius:BorderRadius.circular(9)),child:Text(member?'Hội viên':'Đặt thường',style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:_purple))),
          ])),
        ]),
        const Divider(height:24),
        Row(children:[
          Icon(cancelled?Icons.cancel_outlined:Icons.check_circle_outline,color:cancelled?Colors.redAccent:_purple,size:17),
          const SizedBox(width:7),
          Expanded(child:Text(status,style:TextStyle(fontWeight:FontWeight.w600,fontSize:13,color:cancelled?Colors.redAccent:_purple))),
          TextButton(onPressed:()=>_details(b),child:const Text('Chi tiết ›')),
        ]),
        if(_canPay(b)) ...[
          const SizedBox(height:3),
          Text(_minutesLabel(b),style:const TextStyle(fontWeight:FontWeight.w700,color:Colors.deepOrange,fontSize:13)),
          const SizedBox(height:8),
          SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>_resumePayment(b),icon:const Icon(Icons.payment),label:const Text('Thanh toán ngay'),style:FilledButton.styleFrom(backgroundColor:_purple,minimumSize:const Size.fromHeight(44)))),
        ],
      ]))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible=bookings.expand(_sessions).where((b) {
      if(tab==3) return _cancelled(b);
      if(tab==2) return _past(b);
      if(tab==1) return _upcoming(b);
      return !_cancelled(b);
    }).toList()..sort((a,b) {
      final x=_start(a),y=_start(b);
      if(x==null) return 1;
      if(y==null) return -1;
      return tab==1?x.compareTo(y):y.compareTo(x);
    });
    return Scaffold(backgroundColor:_background,body:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(20,20,20,12),child:Row(children:[
        const Expanded(child:Text('Lịch của tôi',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:_purple))),
        IconButton(onPressed:()=>refresh(),tooltip:'Làm mới',icon:const Icon(Icons.refresh,color:_purple)),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
        for(final item in [(0,'Đã đặt'),(1,'Sắp tới'),(2,'Đã qua'),(3,'Đã huỷ')])
          Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:ChoiceChip(label:Text(item.$2,style:TextStyle(fontSize:12,color:tab==item.$1?Colors.white:_purple)),selected:tab==item.$1,selectedColor:_purple,backgroundColor:Colors.white,showCheckmark:false,onSelected:(_)=>setState(()=>tab=item.$1)))),
      ])),
      if(loading && bookings.isEmpty) const LinearProgressIndicator(),
      if(error!=null) Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:const TextStyle(color:Colors.red))),
      Expanded(child:RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(16),children:[
        if(visible.isEmpty && !loading) const Padding(padding:EdgeInsets.all(30),child:Center(child:Text('Chưa có lịch đặt trong mục này.'))),
        for(final b in visible) ...[
          if (b['sessionKey'] != null && (visible.indexOf(b) == 0 || visible[visible.indexOf(b)-1]['id'] != b['id']))
            Padding(padding: const EdgeInsets.fromLTRB(5,10,5,10),child:Text('Đơn #${b['id']} · ${b['sessionCount']} buổi',style:const TextStyle(color:_purple,fontWeight:FontWeight.w800))),
          _bookingCard(b),
        ],

      ]))),
    ])));
  }
}

class _BookingDetailPage extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String venueName;
  final String? imageUrl;
  final List<Map<String, dynamic>> selections;
  final String statusLabel;
  final bool canPay, canCancel;
  final String? remainingLabel;
  final Future<void> Function() onPay, onCancel, onRefundRequest;

  const _BookingDetailPage({
    required this.booking, required this.venueName, required this.imageUrl,
    required this.selections, required this.statusLabel, required this.canPay,
    required this.canCancel, required this.remainingLabel,
    required this.onPay, required this.onCancel, required this.onRefundRequest,
  });

  bool get member => booking['bookingType'] == 'membership';
  bool get paid => !member && booking['paymentStatus'] == 'paid';
  bool get requested => booking['refundRequestStatus'] == 'pending';
  bool get cancelled => ['cancelled', 'expired'].contains(booking['status']);
  String get price {
    final value = (num.tryParse(booking['totalPrice']?.toString() ?? '') ?? 0).round();
    final digits = value.toString().replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (_) => '.');
    return '$digits đ';
  }

  Widget section(String heading, Widget content) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFEAE6F2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _purple)),
      const SizedBox(height: 14), content,
    ]),
  );

  Widget info(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final first = selections.isNotEmpty ? selections.first : booking;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(title: const Text('Chi tiết đặt sân', style: TextStyle(color: _purple, fontWeight: FontWeight.w800)),
        centerTitle: true, backgroundColor: _background, foregroundColor: _purple),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF35167F), Color(0xFF7452C3)]),
            borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(14),
                child: SizedBox(width: 88, height: 88,
                  child: imageUrl == null
                    ? const ColoredBox(color: Color(0xFFEBE5FA), child: Icon(Icons.sports_tennis, size: 38, color: _purple))
                    : Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.sports_tennis, color: Colors.white)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(venueName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(member ? 'Đặt bằng thẻ hội viên' : 'Đặt sân thường', style: const TextStyle(color: Colors.white70)),
              ])),
            ]),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ])),
          ]),
        ),
        const SizedBox(height: 16),
        if (remainingLabel != null) section('Thời gian thanh toán',
          Text(remainingLabel!, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))),
        if (requested) section('Yêu cầu đang được xử lý',
          const Text('Đã tiếp nhận yêu cầu hoàn 100% theo chính sách huỷ trước 24 giờ. Sân vẫn được giữ cho đến khi có kết quả xử lý.')),
        section('Thông tin đặt sân', Column(children: [
          info('Mã đặt sân', booking['id']?.toString() ?? '-'),
          info('Ngày đặt', first['date']?.toString() ?? '-'),
          for (final s in selections) info('Khung giờ',
            '${s['date']}  •  ${s['startTime']}–${s['endTime'] ?? '-'}  •  Sân ${(s['courtId'] ?? 'court_1').toString().replaceFirst('court_', '')}'),
          info('Số khung giờ', '${selections.length}'),
        ])),
        section('Thanh toán', Column(children: [
          info('Hình thức', member ? 'Thẻ hội viên (trừ ${booking['sessionKey'] != null ? 1 : (booking['membershipUses'] ?? 1)} lượt)' : 'Thanh toán trực tuyến'),
          info('Trạng thái', booking['paymentStatus']?.toString() ?? '-'),
          info('Tổng tiền', member ? '0 đ (${booking['sessionKey'] != null ? 1 : (booking['membershipUses'] ?? 1)} lượt hội viên)' : price),
        ])),
        section('Hỗ trợ', const Text('Đơn đã thanh toán: yêu cầu huỷ trước ít nhất 24 giờ được hoàn 100% sau khi xử lý. Dưới 24 giờ không được hoàn tiền theo chính sách này.')),
        if (canPay) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.icon(onPressed: () async { Navigator.pop(context); await onPay(); },
            icon: const Icon(Icons.payment), label: const Text('Thanh toán ngay'),
            style: FilledButton.styleFrom(backgroundColor: _purple, minimumSize: const Size.fromHeight(48)))),
        if (canCancel) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(onPressed: () async { Navigator.pop(context); await onCancel(); },
            icon: const Icon(Icons.cancel_outlined), label: const Text('Huỷ lịch đặt'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)))),
        if (paid && !cancelled && !requested) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(onPressed: () async { Navigator.pop(context); await onRefundRequest(); },
            icon: const Icon(Icons.support_agent), label: const Text('Yêu cầu huỷ / hoàn tiền'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)))),
      ]),
    );
  }
}
