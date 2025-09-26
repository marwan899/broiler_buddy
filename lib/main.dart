// Broiler Buddy — v0.2 (RTL Arabic UI)
// Flutter 3.x null-safety. Daily logging, targets (Ross/Cobb), FCR/ADG, Iraq-specific HVAC tips.
// NOTE: Storage is in-memory. Replace with Hive/SQLite before production.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BroilerBuddyApp());
}

class BroilerBuddyApp extends StatelessWidget {
  const BroilerBuddyApp({super.key});
  static const String userDisplayName = 'eng marwan';
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Broiler Buddy',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const HomePage(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
    );
  }
}

// --- DATA MODELS ---
class Flock {
  final String name; // مثال: "بيت 1 — Ross 308"
  final DateTime placementDate;
  final int initialChicks; // عدد الصيصان
  final String strain; // Ross 308, Cobb 500
  Flock({required this.name, required this.placementDate, required this.initialChicks, required this.strain});
}

class DayRecord {
  final int day; // عمر الطيور (يوم)
  double houseTempC; // °C على ارتفاع الطير
  double rh; // % رطوبة نسبية
  double feedOfferedKg; // كغم علف مقدم
  double feedRefusedKg; // كغم هدر/متبقي
  int mortalities; // نافق يومي (عدد)
  double avgWeightG; // وزن متوسط العينة (غم)
  DayRecord({
    required this.day,
    required this.houseTempC,
    required this.rh,
    required this.feedOfferedKg,
    this.feedRefusedKg = 0,
    this.mortalities = 0,
    required this.avgWeightG,
  });
}

class TargetRow {
  final int day;
  final double targetBWg; // وزن هدف (غم)
  final double targetCumFeedKgPerBird; // استهلاك تراكمي/طير (كغم)
  final double targetTempC; // setpoint °C
  final double minRH; // RH الأدنى
  final double maxRH; // RH الأعلى
  const TargetRow(this.day, this.targetBWg, this.targetCumFeedKgPerBird, this.targetTempC, this.minRH, this.maxRH);
}

class TargetTables {
  // Ross 308 — نقاط مفتاحية (مثال مبسّط). كمّل باقي الأيام حسب الدليل.
  static const List<TargetRow> ross308 = [
    TargetRow(1, 46, 0.05, 32, 50, 70),
    TargetRow(3, 98, 0.12, 31, 50, 70),
    TargetRow(7, 180, 0.20, 29, 50, 70),
    TargetRow(10, 310, 0.36, 27, 50, 70),
    TargetRow(14, 455, 0.57, 26, 50, 70),
    TargetRow(21, 930, 1.14, 23, 50, 70),
    TargetRow(28, 1550, 1.90, 21, 50, 70),
    TargetRow(35, 2250, 2.80, 20, 50, 70),
    TargetRow(42, 2950, 3.80, 20, 50, 70),
    TargetRow(49, 3550, 4.75, 20, 50, 70),
  ];

  // Cobb 500 — نقاط مفتاحية (قِيَم تقريبية شائعة للعرض؛ استبدلها بالقيم الموثّقة لديك).
  static const List<TargetRow> cobb500 = [
    TargetRow(1, 45, 0.05, 32, 50, 70),
    TargetRow(3, 95, 0.11, 31, 50, 70),
    TargetRow(7, 175, 0.19, 29, 50, 70),
    TargetRow(10, 300, 0.34, 27, 50, 70),
    TargetRow(14, 440, 0.54, 26, 50, 70),
    TargetRow(21, 900, 1.10, 23, 50, 70),
    TargetRow(28, 1500, 1.85, 21, 50, 70),
    TargetRow(35, 2200, 2.75, 20, 50, 70),
    TargetRow(42, 2900, 3.70, 20, 50, 70),
    TargetRow(49, 3500, 4.60, 20, 50, 70),
  ];

  static TargetRow? findByDay(List<TargetRow> table, int day) {
    TargetRow? nearest;
    for (final row in table) {
      if (row.day <= day) nearest = row;
    }
    return nearest;
  }
}

// --- REPO (In‑Memory) ---
class Repo extends ChangeNotifier {
  Flock? flock;
  final List<DayRecord> records = [];

  void setFlock(Flock f) { flock = f; notifyListeners(); }

  void upsertRecord(DayRecord r) {
    records.removeWhere((e) => e.day == r.day);
    records.add(r);
    records.sort((a, b) => a.day.compareTo(b.day));
    notifyListeners();
  }

  int get placed => flock?.initialChicks ?? 0;
  int get totalMort => records.fold(0, (s, r) => s + r.mortalities);
  int get remainingBirds => (placed - totalMort).clamp(0, 1000000);

  double get cumulativeFeedKg => records.fold(0.0, (s, r) => s + (r.feedOfferedKg - r.feedRefusedKg));
  double get cumulativeFeedPerBirdKg => remainingBirds > 0 ? cumulativeFeedKg / remainingBirds : 0.0;

  double? get latestAvgWeightG => records.isEmpty ? null : records.last.avgWeightG;
  double? get bwGainG => (latestAvgWeightG != null && records.isNotEmpty)
      ? (latestAvgWeightG! - records.first.avgWeightG)
      : null;

  double? get fcr {
    if (records.length < 2 || latestAvgWeightG == null || remainingBirds <= 0) return null;
    final initWkg = records.first.avgWeightG / 1000.0;
    final lastWkg = records.last.avgWeightG / 1000.0;
    final gainPerBirdKg = (lastWkg - initWkg).clamp(0.0, 1000.0);
    final totalGainKg = gainPerBirdKg * remainingBirds;
    if (totalGainKg <= 0) return null;
    return cumulativeFeedKg / totalGainKg;
  }

  double? get adgGPerDay {
    if (records.length < 2) return null;
    final last = records.last;
    final first = records.length > 7 ? records[records.length - 8] : records.first;
    final days = (last.day - first.day).clamp(1, 120);
    return (last.avgWeightG - first.avgWeightG) / days;
  }
}

// --- UI ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final repo = Repo();
  int _tab = 0;
  bool _greeted = false;

  @override
  Widget build(BuildContext context) {
    final pages = [
      SetupPage(repo: repo),
      LogPage(repo: repo),
      DashboardPage(repo: repo),
      TargetsPage(getTable: () {
        final s = repo.flock?.strain ?? 'Ross 308';
        return s.contains('Cobb') ? TargetTables.cobb500 : TargetTables.ross308;
      }),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Broiler Buddy — دليل المربّي'),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: 12),
              child: Center(child: Text('مرحبا، eng marwan', style: TextStyle(fontWeight: FontWeight.w600))),
            )
          ],
        ),
        body: Builder(builder: (ctx){
          if(!_greeted){
            WidgetsBinding.instance.addPostFrameCallback((_){
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أهلاً eng marwan — جاهزين نبدأ الدفعة اليوم؟')));
            });
            _greeted = true;
          }
          return pages[_tab];
        }),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.settings), label: 'إعداد القطيع'),
            NavigationDestination(icon: Icon(Icons.edit), label: 'سجل يومي'),
            NavigationDestination(icon: Icon(Icons.assessment), label: 'لوحة التحكم'),
            NavigationDestination(icon: Icon(Icons.flag), label: 'الأهداف'),
          ],
          onDestinationSelected: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

class SetupPage extends StatefulWidget {
  final Repo repo;
  const SetupPage({super.key, required this.repo});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final nameC = TextEditingController(text: 'بيت 1 — Ross 308');
  final chicksC = TextEditingController(text: '5000');
  DateTime placement = DateTime.now();
  String strain = 'Ross 308';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        TextField(controller: nameC, decoration: const InputDecoration(labelText: 'اسم القطيع/البيت')),
        TextField(controller: chicksC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الصيصان المدخلة')),
        const SizedBox(height: 8),
        DropdownButtonFormField(
          value: strain,
          items: const [
            DropdownMenuItem(value: 'Ross 308', child: Text('Ross 308')),
            DropdownMenuItem(value: 'Cobb 500', child: Text('Cobb 500')),
          ],
          onChanged: (v) => setState(() => strain = v as String),
          decoration: const InputDecoration(labelText: 'السلالة'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: placement,
              locale: const Locale('ar'),
            );
            if (picked != null) setState(() => placement = picked);
          },
          icon: const Icon(Icons.date_range),
          label: Text('تاريخ الإدخال: ${placement.toString().substring(0, 10)}'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final f = Flock(
              name: nameC.text.trim(),
              placementDate: placement,
              initialChicks: int.tryParse(chicksC.text.trim()) ?? 0,
              strain: strain,
            );
            widget.repo.setFlock(f);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعداد القطيع')));
          },
          child: const Text('حفظ'),
        ),
      ]),
    );
  }
}

class LogPage extends StatefulWidget {
  final Repo repo;
  const LogPage({super.key, required this.repo});
  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final dayC = TextEditingController();
  final tC = TextEditingController();
  final rhC = TextEditingController();
  final feedOfferC = TextEditingController();
  final feedRefuseC = TextEditingController();
  final mortC = TextEditingController(text: '0');
  final bwC = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Row(children: [
          Expanded(child: TextField(controller: dayC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العمر/يوم'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: bwC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الوزن المتوسط (غم)'))),
        ]),
        Row(children: [
          Expanded(child: TextField(controller: tC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحرارة °C'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: rhC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الرطوبة %'))),
        ]),
        Row(children: [
          Expanded(child: TextField(controller: feedOfferC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العلف المقدم (كغم)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: feedRefuseC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المتبقي/الهدر (كغم)'))),
        ]),
        TextField(controller: mortC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'النافق اليومي (عدد)')),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            final rec = DayRecord(
              day: int.tryParse(dayC.text.trim()) ?? 1,
              houseTempC: double.tryParse(tC.text.trim()) ?? 0,
              rh: double.tryParse(rhC.text.trim()) ?? 0,
              feedOfferedKg: double.tryParse(feedOfferC.text.trim()) ?? 0,
              feedRefusedKg: double.tryParse(feedRefuseC.text.trim()) ?? 0,
              mortalities: int.tryParse(mortC.text.trim()) ?? 0,
              avgWeightG: double.tryParse(bwC.text.trim()) ?? 0,
            );
            widget.repo.upsertRecord(rec);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ السجل اليومي')));
          },
          icon: const Icon(Icons.save),
          label: const Text('حفظ'),
        ),
        const SizedBox(height: 16),
        ...widget.repo.records.map((r) {
          final netFeed = (r.feedOfferedKg - r.feedRefusedKg).clamp(0.0, 1e9);
          final birds = widget.repo.remainingBirds == 0 ? widget.repo.placed : widget.repo.remainingBirds;
          final feedPerBird = birds > 0 ? netFeed / birds : 0.0;
          return ListTile(
            title: Text('يوم ${r.day} — وزن ${r.avgWeightG.toStringAsFixed(0)} غم'),
            subtitle: Text('T=${r.houseTempC}°C • RH=${r.rh}%\nعلف صافٍ=${netFeed.toStringAsFixed(2)} كغم (=${(feedPerBird * 1000).toStringAsFixed(1)} غم/طير) • نافق=${r.mortalities}'),
          );
        }),
      ]),
    );
  }
}

class DashboardPage extends StatelessWidget {
  final Repo repo;
  const DashboardPage({super.key, required this.repo});

  List<TargetRow> _table() {
    final s = repo.flock?.strain ?? 'Ross 308';
    return s.contains('Cobb') ? TargetTables.cobb500 : TargetTables.ross308;
  }

  String _iraqVentHeatGuidance({required int day, required double t, required double rh}) {
    // تبسيط عملي: تقسيم موسمي حسب الأشهر (حرّ: أيار–أيلول، برد: كانون 1–شباط، معتدل: غيرها)
    final m = DateTime.now().month;
    final isHot = m >= 5 && m <= 9;
    final isCold = m == 12 || m <= 2;

    final List<String> tips = [];
    // قواعد عامة حسب RH/الحرارة
    if (rh > 70) tips.add('الرطوبة مرتفعة: زِد換 الهواء تدريجيًا وقلّل الرذاذ؛ تجنّب البلل تحت المُعَلِّفات.');
    if (rh < 50) tips.add('الرطوبة منخفضة: خفّف換 الهواء، وفعّل رذاذ خفيف/تبخير عند اللزوم لتقليل الغبار.');

    if (isHot) {
      tips.addAll([
        'موسم حار: تهوية نفقية مساءً/ليلًا لخفض الحمل الحراري، وزِد السرعة الهوائية > 2 م/ث عند الذروة.',
        'تبريد تبخيري/فوجرز نهاريًا عند T>30°C مع مراقبة RH كي لا تتجاوز 75%.',
        'وفّر ماء بارد نظيف (≤20°C) واغسل خطوط الماء يوميًا؛ السرعة الهوائية عامل حاسم.',
      ]);
      if (t >= 30 && rh >= 65) tips.add('خطر إجهاد حراري: خفّض الكثافة حول المعالف، زد نقاط الشرب، وابدأ تهوية تعزيزية قبل الظهر.');
    } else if (isCold) {
      tips.addAll([
        'موسم بارد: سخّن البيت قبل الإدخال بساعتين؛ حافظ على فرشة جافة دافئة للصيصان.',
        'Minimum Ventilation: نبضات مراوح قصيرة متكررة لطرد الرطوبة/الأمونيا دون إسقاط حرارة.',
        'سدّ التسريبات لضمان مسار هوائي صحيح والسحب من المناور العلوية.',
      ]);
      if (t < 24 && day <= 7) tips.add('حضّانة: إذا T<24°C بعمر مبكّر، زِد مصادر التدفئة واضبط ارتفاع الدفايات.');
    } else {
      tips.addAll([
        'موسم معتدل: تهوية متوازنة تُبقي RH بين 50–70% مع حرارة قريبة من setpoint.',
        'بدّل بين عرضية/نفقية حسب الرياح الخارجية وحمل البيت.',
      ]);
    }

    if (day <= 7 && t > 32) tips.add('صيصان ≤7 أيام: الحرارة عالية؛ راقب تجمع بعيدًا عن السخانات وزّع الحرارة بالتساوي.');
    if (day >= 28 && t > 28) tips.add('أعمار كبيرة: حسّاسون؛ زِد سرعة الهواء والتهوية النفقية وتجنّب RH>70%.');

    if (tips.isEmpty) tips.add('الظروف ضمن المقبول؛ استمر على تهوية متوازنة ومراقبة سلوك الطيور.');
    return tips.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final day = repo.records.isEmpty ? null : repo.records.last.day;
    final target = day == null ? null : TargetTables.findByDay(_table(), day);

    final fcr = repo.fcr;
    final adg = repo.adgGPerDay;

    String envAdvisory() {
      if (repo.records.isEmpty || target == null) return '—';
      final r = repo.records.last;
      final notes = <String>[];
      if (r.houseTempC > target!.targetTempC + 1.5) notes.add('حرارة أعلى من الهدف ➜ زِد التهوية والرذاذ تدريجيًا');
      if (r.houseTempC < target!.targetTempC - 1.5) notes.add('حرارة أقل من الهدف ➜ فعّل تدفئة وقلّل السحب');
      if (r.rh > target!.maxRH) notes.add('RH مرتفع (> ${target!.maxRH}%) ➜ تحكم بالرذاذ وزِد換 الهواء');
      if (r.rh < target!.minRH) notes.add('RH منخفض (< ${target!.minRH}%) ➜ قلّل換 الهواء أو زد الترطيب');
      if (notes.isEmpty) return 'الظروف ضمن النطاق المستهدف';
      return notes.join(' • ');
    }

    String perfNote() {
      if (repo.records.isEmpty || target == null) return '—';
      final bw = repo.records.last.avgWeightG;
      final diff = bw - target!.targetBWg;
      final sign = diff >= 0 ? '+' : '';
      return 'الوزن مقابل الهدف: ${sign}${diff.toStringAsFixed(0)} غم';
    }

    String feedNote() {
      if (repo.records.isEmpty || target == null) return '—';
      final cumPerBird = repo.cumulativeFeedPerBirdKg; // كغم/طير
      final diff = (cumPerBird - target!.targetCumFeedKgPerBird) * 1000; // غم/طير
      final sign = diff >= 0 ? '+' : '';
      return 'الاستهلاك التراكمي/طير: ${(cumPerBird * 1000).toStringAsFixed(0)} غم (فرق ${sign}${diff.toStringAsFixed(0)} غم)';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Card(child: ListTile(leading: const Icon(Icons.person_pin), title: const Text('المستخدم'), subtitle: const Text('eng marwan'))),
        Card(child: ListTile(title: const Text('الحالة البيئية'), subtitle: Text(envAdvisory()), trailing: const Icon(Icons.thermostat))),
        Card(
          child: ListTile(
            title: const Text('إرشادات العراق (تهوية/تدفئة)'),
            subtitle: Text(
              repo.records.isEmpty
                  ? 'أدخل قياسات اليوم لعرض توصيات مخصصة.'
                  : _iraqVentHeatGuidance(day: repo.records.last.day, t: repo.records.last.houseTempC, rh: repo.records.last.rh),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.air),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('الأداء الإنتاجي'),
            subtitle: Text('${perfNote()}\n${feedNote()}\nFCR (تراكمي): ${fcr == null ? '—' : fcr!.toStringAsFixed(3)}\nADG (غم/يوم): ${adg == null ? '—' : adg!.toStringAsFixed(1)}'),
            isThreeLine: true,
            trailing: const Icon(Icons.trending_up),
          ),
        ),
        Card(child: ListTile(title: const Text('الطيور المتبقية'), subtitle: Text('${repo.remainingBirds} من ${repo.placed} (نافق ${repo.totalMort})'), trailing: const Icon(Icons.pets))),
        const SizedBox(height: 8),
        const Text('تنبيه: الأهداف الحالية نقاط مفتاحية. عَبّي كامل الأيام (1–42/49) من دليل السلالة المستخدم لديك للحصول على دقة أعلى.'),
      ]),
    );
  }
}

class TargetsPage extends StatelessWidget {
  final List<TargetRow> Function() getTable;
  const TargetsPage({super.key, required this.getTable});
  @override
  Widget build(BuildContext context) {
    final rows = getTable();
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        return ListTile(
          title: Text('يوم ${r.day} — وزن هدف ${r.targetBWg.toStringAsFixed(0)} غم'),
          subtitle: Text('علف تراكمي/طير ${r.targetCumFeedKgPerBird.toStringAsFixed(2)} كغم — حرارة ${r.targetTempC}°C — RH ${r.minRH.toStringAsFixed(0)}–${r.maxRH.toStringAsFixed(0)}%'),
        );
      },
    );
  }
}
