import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const purple=Color(0xFF361A94);
  static const bg=Color(0xFFFFFEF7);
  List<Map<String,dynamic>> items=[];
  bool loading=true;
  String? error;

  @override
  void initState(){super.initState();load();}
  Future<String> _jwt() async {
    final token=await FirebaseAuth.instance.currentUser?.getIdToken();
    if(token==null||token.isEmpty)throw Exception('Vui lòng đăng nhập lại.');
    return token;
  }
  Future<void> load() async {
    setState(() {loading=true;error=null;});
    try {
      final token=await _jwt();
      final res=await http.get(Uri.parse('${ApiClient.baseUrl}/notifications'),headers:{'Authorization':'Bearer $token'})
          .timeout(const Duration(seconds:15));
      final obj=jsonDecode(utf8.decode(res.bodyBytes));
      if(res.statusCode!=200||obj is! Map||obj['success']!=true||obj['notifications'] is! List){
        throw Exception(obj is Map ? obj['message']?.toString()??'Không tải được thông báo.' : 'Dữ liệu lỗi.');
      }
      if(!mounted)return;
      setState(()=>items=(obj['notifications'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList());
    }catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> _markRead(Map<String,dynamic> item) async {
    if(item['read']==true)return;
    final id=item['id']?.toString()??'';
    try{
      final token=await _jwt();
      final response=await http.post(Uri.parse('${ApiClient.baseUrl}/notifications/${Uri.encodeComponent(id)}/read'),
        headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:12));
      if(response.statusCode!=200)throw Exception('Không cập nhật được thông báo');
      if(mounted)setState(()=>item['read']=true);
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  Future<void> _readAll() async {
    try{
      final token=await _jwt();
      final response=await http.post(Uri.parse('${ApiClient.baseUrl}/notifications/read-all'),
        headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:12));
      if(response.statusCode!=200)throw Exception('Không cập nhật được thông báo');
      await load();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  String _dateLabel(dynamic raw) {
    final date=DateTime.tryParse(raw?.toString()??'')?.toLocal();
    if(date==null)return '';
    final d='${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}';
    return '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')} · $d';
  }
  @override
  Widget build(BuildContext context) {
    final unread=items.where((e)=>e['read']!=true).length;
    return Scaffold(
      backgroundColor:bg,
      appBar:AppBar(
        backgroundColor:bg,centerTitle:true,elevation:0,surfaceTintColor:Colors.transparent,
        leading:IconButton(onPressed:()=>Navigator.of(context).pop(),icon:const Icon(Icons.arrow_back_ios_new_rounded,size:18,color:purple)),
        title:const Text('Thông báo',style:TextStyle(fontSize:16,fontWeight:FontWeight.w700,color:purple)),
      ),
      body:RefreshIndicator(onRefresh:load,color:purple,child:Column(children:[
        if(items.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),child:Row(children:[
          Text(unread>0?'$unread thông báo chưa đọc':'Tất cả đã đọc',style:const TextStyle(fontSize:12,color:Color(0xFF77748E))),
          const Spacer(),TextButton(onPressed:unread==0?null:_readAll,child:const Text('Đánh dấu đã đọc',style:TextStyle(fontSize:12,color:purple)))
        ])),
        Expanded(child:loading?const Center(child:CircularProgressIndicator(color:purple))
          :error!=null?ListView(children:[const SizedBox(height:100),const Icon(Icons.wifi_off_rounded,size:44,color:Color(0xFFAAA3C4)),
            const SizedBox(height:16),Center(child:Text(error!,textAlign:TextAlign.center,style:const TextStyle(fontSize:12))),
            Center(child:TextButton(onPressed:load,child:const Text('Thử lại')))])
          :items.isEmpty?ListView(children:const [SizedBox(height:110),Icon(Icons.notifications_none_rounded,size:58,color:Color(0xFFB5A9DE)),SizedBox(height:16),
            Center(child:Text('Chưa có thông báo',style:TextStyle(color:purple,fontSize:15,fontWeight:FontWeight.w700))),SizedBox(height:8),
            Center(child:Padding(padding:EdgeInsets.symmetric(horizontal:36),child:Text('Khi có lịch sắp đến giờ chơi, thông báo sẽ xuất hiện tại đây.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF77748E),fontSize:12))))])
          :ListView.separated(padding:const EdgeInsets.fromLTRB(16,8,16,24),itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(ctx,index){
              final item=items[index];final read=item['read']==true;
              return InkWell(onTap:()=>_markRead(item),borderRadius:BorderRadius.circular(15),child:Container(
                padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:read?Colors.white:const Color(0xFFF2EDFF),
                  borderRadius:BorderRadius.circular(15),border:Border.all(color:read?const Color(0xFFE7E2F0):const Color(0xFFD2C3FF))),
                child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Container(width:38,height:38,decoration:BoxDecoration(color:const Color(0xFFE5DCFF),borderRadius:BorderRadius.circular(11)),
                    child:const Icon(Icons.event_available_rounded,color:purple,size:20)),const SizedBox(width:11),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(item['title']?.toString()??'SPORTY',style:TextStyle(color:purple,fontWeight:read?FontWeight.w600:FontWeight.w700,fontSize:13)),
                    const SizedBox(height:5),Text(item['body']?.toString()??'',style:const TextStyle(fontSize:12,height:1.35,color:Color(0xFF303044))),
                    const SizedBox(height:8),Text(_dateLabel(item['createdAt']),style:const TextStyle(fontSize:10,color:Color(0xFF858097)))
                  ])),if(!read)const Padding(padding:EdgeInsets.only(left:6,top:5),child:CircleAvatar(radius:4,backgroundColor:purple))
                ])));
            }))
      ])),
    );
  }
}
