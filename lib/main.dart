import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(ChangeNotifierProvider(create: (_) => KhataProvider()..load(), child: const KhataApp()));
}

class KhataApp extends StatelessWidget {
  const KhataApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Khata PRO',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF00695C), textTheme: GoogleFonts.poppinsTextTheme()),
      home: const HomePage(),
    );
  }
}

class KhataEntry {
  String id, name, note; int amount; bool isUdhar; DateTime date;
  KhataEntry({required this.id, required this.name, required this.amount, required this.isUdhar, required this.date, this.note=''});
  Map<String,dynamic> toMap() => {'id':id,'name':name,'amount':amount,'isUdhar':isUdhar,'date':date.toIso8601String(),'note':note};
  factory KhataEntry.fromMap(Map m) => KhataEntry(id:m['id'], name:m['name'], amount:m['amount'], isUdhar:m['isUdhar'], date:DateTime.parse(m['date']), note:m['note']??'');
}

class KhataProvider extends ChangeNotifier {
  List<KhataEntry> entries = [];
  String familyId = "FAMILY-2026-001";
  SpeechToText speech = SpeechToText();
  bool isListening = false;
  String voiceText = "";

  Future load() async {
    final pref = await SharedPreferences.getInstance();
    familyId = pref.getString('familyId')?? "FAMILY-2026-001";
    var data = pref.getString('khata_data');
    if(data!=null){
      List list = jsonDecode(data);
      entries = list.map((e)=>KhataEntry.fromMap(e)).toList();
      entries.sort((a,b)=>b.date.compareTo(a.date));
    }
    notifyListeners();
  }
  Future save() async {
    final pref = await SharedPreferences.getInstance();
    pref.setString('khata_data', jsonEncode(entries.map((e)=>e.toMap()).toList()));
    pref.setString('familyId', familyId);
  }
  Future addEntry(String name, int amount, bool isUdhar, String note) async {
    entries.insert(0, KhataEntry(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name.trim(), amount: amount, isUdhar: isUdhar, date: DateTime.now(), note: note));
    notifyListeners(); await save();
  }
  void deleteEntry(String id){ entries.removeWhere((e)=>e.id==id); notifyListeners(); save(); }
  int get totalUdhar => entries.where((e)=>e.isUdhar).fold(0, (s,e)=>s+e.amount);
  int get totalJama => entries.where((e)=>!e.isUdhar).fold(0, (s,e)=>s+e.amount);
  int get balance => totalJama - totalUdhar;
  Map<String,int> get chartData { Map<String,int> m={}; for(var e in entries){ if(e.isUdhar) m[e.name]=(m[e.name]??0)+e.amount; } return m; }
  Future startVoice(Function(String) onResult) async { bool ok = await speech.initialize(); if(ok){ isListening=true; notifyListeners(); speech.listen(onResult: (r){ voiceText=r.recognizedWords; onResult(voiceText); notifyListeners(); }); } }
  void stopVoice(){ speech.stop(); isListening=false; notifyListeners(); }
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  int idx=0;
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text("MUMMY KA KHATA PRO"), centerTitle:true, actions:[
        IconButton(onPressed: () async {
          var p=context.read<KhataProvider>();
          final pdf = pw.Document();
          pdf.addPage(pw.Page(build: (c)=>pw.Column(children:[pw.Text("Khata PRO Report - ${DateFormat('dd MMM yyyy').format(DateTime.now())}", style:pw.TextStyle(fontSize:20, fontWeight:pw.FontWeight.bold)), pw.SizedBox(height:20), pw.Text("Udhar: ${p.totalUdhar} | Jama: ${p.totalJama} | Balance: ${p.balance}"), pw.Divider(),...p.entries.map((e)=>pw.Text("${e.name} - ${e.isUdhar?'Diya':'Liya'} - Rs.${e.amount} - ${DateFormat('dd/MM').format(e.date)}")))])));
          await Printing.sharePdf(bytes: await pdf.save(), filename: 'khata.pdf');
        }, icon: const Icon(Icons.picture_as_pdf)),
        IconButton(onPressed: (){ var id=context.read<KhataProvider>().familyId; Share.share("Mere Khata PRO me join karo! Family ID: $id\nTotal Udhar: ${context.read<KhataProvider>().totalUdhar}"); }, icon: const Icon(Icons.share)),
      ]),
      body: [KhataList(), StatsPage(), FamilyPage()][idx],
      bottomNavigationBar: NavigationBar(selectedIndex: idx, onDestinationSelected: (i)=>setState(()=>idx=i), destinations: const [
        NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: "Khata"),
        NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: "Graph"),
        NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: "Family"),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: ()=>showAddDialog(context), icon: const Icon(Icons.add), label: const Text("ADD ENTRY")),
    );
  }
}

class KhataList extends StatelessWidget {
  @override Widget build(BuildContext context){
    var p=context.watch<KhataProvider>();
    if(p.entries.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.book, size:80, color: Colors.grey.shade300), const SizedBox(height:10), const Text("Koi entry nahi hai\n'ADD ENTRY' dabao ya bolo '500 Ramesh ko diye'", textAlign: TextAlign.center)]));
    return Column(children:[
      Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF00695C), borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children:[
        _bal("Udhar", p.totalUdhar, Colors.redAccent), Container(width:1, height:40, color:Colors.white24), _bal("Jama", p.totalJama, Colors.greenAccent), Container(width:1, height:40, color:Colors.white24), _bal("Baki", p.balance, Colors.white),
      ])),
      Expanded(child: ListView.builder(itemCount: p.entries.length, itemBuilder: (_,i){ var e=p.entries[i]; return Dismissible(key: Key(e.id), direction: DismissDirection.endToStart, onDismissed: (_)=>p.deleteEntry(e.id), background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right:20), child: const Icon(Icons.delete, color: Colors.white)), child: Card(margin: const EdgeInsets.symmetric(horizontal:12, vertical:6), child: ListTile(leading: CircleAvatar(backgroundColor: e.isUdhar?Colors.red.shade100:Colors.green.shade100, child: Icon(e.isUdhar?Icons.arrow_upward:Icons.arrow_downward, color: e.isUdhar?Colors.red:Colors.green)), title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("${DateFormat('dd MMM, hh:mm a').format(e.date)} • ${e.note}"), trailing: Text("₹${e.amount}", style: TextStyle(fontWeight: FontWeight.bold, fontSize:18, color: e.isUdhar?Colors.red:Colors.green))))); }))
    ]);
  }
  Widget _bal(String t, int v, Color c)=>Column(children:[Text(t, style: const TextStyle(color: Colors.white70, fontSize:12)), const SizedBox(height:4), Text("₹$v", style: TextStyle(color: c, fontSize:18, fontWeight: FontWeight.bold))]);
}

class StatsPage extends StatelessWidget {
  @override Widget build(BuildContext context){
    var map=context.watch<KhataProvider>().chartData;
    if(map.isEmpty) return const Center(child: Text("Graph ke liye data nahi"));
    var list=map.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    var top=list.take(5).toList();
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Text("Top 5 Udhar - Kisko sabse zyada diya", style: GoogleFonts.poppins(fontSize:16, fontWeight: FontWeight.bold)),
      const SizedBox(height:20),
      SizedBox(height:260, child: BarChart(BarChartData(barGroups: List.generate(top.length, (i)=>BarChartGroupData(x:i, barRods:[BarChartRodData(toY: top[i].value.toDouble(), color: const Color(0xFF00695C), width:22, borderRadius: BorderRadius.circular(6))])), titlesData: FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles:true, reservedSize:40, getTitlesWidget: (v,_)=>Text("₹${v.toInt()}", style: const TextStyle(fontSize:10)))), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles:true, getTitlesWidget: (v,_)=>Padding(padding: const EdgeInsets.only(top:4), child: Text(top[v.toInt()].key.length>6?top[v.toInt()].key.substring(0,6):top[v.toInt()].key, style: const TextStyle(fontSize:10))))), borderData: FlBorderData(show:false), gridData: const FlGridData(show:false)))),
      const SizedBox(height:20),
     ...list.map((e)=>ListTile(title: Text(e.key), trailing: Text("₹${e.value}", style: const TextStyle(fontWeight: FontWeight.bold))))
    ]));
  }
}

class FamilyPage extends StatelessWidget {
  @override Widget build(BuildContext context){
    var p=context.watch<KhataProvider>();
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[
      const Icon(Icons.family_restroom, size:90, color: Color(0xFF00695C)), const SizedBox(height:20),
      const Text("Family Sharing ID", style: TextStyle(fontSize:20, fontWeight: FontWeight.bold)),
      const SizedBox(height:10),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal)), child: SelectableText(p.familyId, style: const TextStyle(fontSize:22, fontWeight: FontWeight.bold, letterSpacing:2))),
      const SizedBox(height:12), const Text("Is ID ko ghar walon me share karo.\nSabka hisab ek sath dekho.", textAlign: TextAlign.center),
      const SizedBox(height:20), ElevatedButton.icon(onPressed: ()=>Share.share("Khata PRO Family ID: ${p.familyId}"), icon: const Icon(Icons.share), label: const Text("Share Family ID")),
    ])));
  }
}

void showAddDialog(BuildContext context){
  TextEditingController nameC=TextEditingController(), amountC=TextEditingController(), noteC=TextEditingController();
  bool isUdhar=true; var prov=context.read<KhataProvider>();
  void parseVoice(String txt){
    txt=txt.toLowerCase(); var num=RegExp(r'(\d+)').firstMatch(txt); if(num!=null) amountC.text=num.group(1)!;
    if(txt.contains("liya")||txt.contains("jama")||txt.contains("mila")) isUdhar=false;
    if(txt.contains("diya")||txt.contains("udhar")) isUdhar=true;
    if(txt.contains("ko")){ var parts=txt.split("ko")[0].trim().split(" "); if(parts.isNotEmpty) nameC.text=parts.last; }
  }
  showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx){
    return StatefulBuilder(builder: (ctx,setSt){
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left:16, right:16, top:16), child: Consumer<KhataProvider>(builder: (_,pr,__){
        return Column(mainAxisSize: MainAxisSize.min, children:[
          Row(children:[const Text("Nayi Entry", style: TextStyle(fontSize:20, fontWeight: FontWeight.bold)), const Spacer(), InkWell(onTap: () async { if(!pr.isListening){ await pr.startVoice((t){ parseVoice(t); setSt((){}); }); } else { pr.stopVoice(); } }, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: pr.isListening?Colors.red:Colors.teal, shape: BoxShape.circle), child: Icon(pr.isListening?Icons.mic:Icons.mic_none, color: Colors.white)))]),
          if(pr.isListening) Padding(padding: const EdgeInsets.all(8), child: Text("Sun raha hu: ${pr.voiceText}", style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))),
          const Text("Try bolo: '500 Rupye Ramesh ko diye'", style: TextStyle(fontSize:11, color: Colors.grey)),
          const SizedBox(height:12),
          TextField(controller: nameC, decoration: const InputDecoration(labelText: "Naam (Ramesh)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
          const SizedBox(height:10),
          TextField(controller: amountC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Rakam", border: OutlineInputBorder(), prefixText: "₹ ", prefixIcon: Icon(Icons.currency_rupee))),
          const SizedBox(height:10),
          Row(children:[ChoiceChip(label: const Text("Udhar Diya"), selected: isUdhar, onSelected: (v)=>setSt(()=>isUdhar=true)), const SizedBox(width:10), ChoiceChip(label: const Text("Jama Liya"), selected:!isUdhar, onSelected: (v)=>setSt(()=>isUdhar=false))]),
          const SizedBox(height:10),
          TextField(controller: noteC, decoration: const InputDecoration(labelText: "Note (optional)", border: OutlineInputBorder())),
          const SizedBox(height:16),
          SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00695C), foregroundColor: Colors.white, padding: const EdgeInsets.all(16)), onPressed: (){ if(nameC.text.isNotEmpty && amountC.text.isNotEmpty){ prov.addEntry(nameC.text, int.tryParse(amountC.text)??0, isUdhar, noteC.text); Navigator.pop(ctx);} }, child: const Text("SAVE KARO", style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height:20),
        ]);
      }));
    });
  });
}
