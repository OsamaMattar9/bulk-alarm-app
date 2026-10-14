import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  runApp(const BulkAlarmApp());
}

class BulkAlarmApp extends StatelessWidget {
  const BulkAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مولد المنبهات المتسلسلة',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
      ),
      home: const BulkAlarmScreen(),
    );
  }
}

class BulkAlarmScreen extends StatefulWidget {
  const BulkAlarmScreen({super.key});

  @override
  State<BulkAlarmScreen> createState() => _BulkAlarmScreenState();
}

class _BulkAlarmScreenState extends State<BulkAlarmScreen> {
  TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
  final TextEditingController countController = TextEditingController(text: '70');
  final TextEditingController intervalController = TextEditingController(text: '2');
  final TextEditingController snoozeController = TextEditingController(text: '5');

  String? selectedRingtonePath;
  String selectedRingtoneName = 'لم يتم اختيار نغمة بعد (اضغط للاختيار)';

  bool isGenerating = false;
  List<AlarmSettings> activeAlarms = [];
  StreamSubscription<dynamic>? ringSubscription;

  @override
  void initState() {
    super.initState();
    loadAlarms();
    // ignore: deprecated_member_use
    ringSubscription = Alarm.ringStream.stream.listen((alarmSettings) {
      _showRingingDialog(alarmSettings);
    });
  }

  Future<void> loadAlarms() async {
    final alarms = await Alarm.getAlarms();
    setState(() {
      activeAlarms = alarms;
    });
  }

  @override
  void dispose() {
    ringSubscription?.cancel();
    countController.dispose();
    intervalController.dispose();
    snoozeController.dispose();
    super.dispose();
  }

  // اختيار نغمة موحدة من ملفات التلفون (متوافق مع التحديث الجديد)
  Future<void> pickRingtone() async {
    final result = await (FilePicker as dynamic).pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      setState(() {
        selectedRingtonePath = result.files.single.path!;
        selectedRingtoneName = result.files.single.name;
      });
    }
  }

  // توليد سلسلة المنبهات دفعة واحدة
  Future<void> generateAlarms() async {
    if (selectedRingtonePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ الرجاء اختيار نغمة المنبه أولاً من الزر بالأعلى!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => isGenerating = true);

    final int count = int.tryParse(countController.text) ?? 10;
    final int intervalMinutes = int.tryParse(intervalController.text) ?? 2;

    await Alarm.stopAll();

    final now = DateTime.now();
    DateTime baseDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    );

    if (baseDateTime.isBefore(now)) {
      baseDateTime = baseDateTime.add(const Duration(days: 1));
    }

    for (int i = 0; i < count; i++) {
      final alarmTime = baseDateTime.add(Duration(minutes: i * intervalMinutes));
      final alarmId = i + 1;

      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: alarmTime,
        assetAudioPath: selectedRingtonePath!,
        loopAudio: true,
        vibrate: true,
        volumeSettings: VolumeSettings.fixed(volume: 1.0),
        notificationSettings: NotificationSettings(
          title: 'منبه رقم $alarmId من $count',
          body: 'اضغط للغفوة أو لإلغاء باقي المنبهات',
          stopButton: 'إيقاف هذا المنبه',
        ),
      );

      await Alarm.set(alarmSettings: alarmSettings);
    }

    await loadAlarms();
    setState(() => isGenerating = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تفعيل $count منبه بنجاح! بفاصل $intervalMinutes دقيقة'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // شاشة الرنين (تحتوي على الغفوة + إلغاء كل المتبقي)
  void _showRingingDialog(AlarmSettings ringingAlarm) {
    final int snoozeMinutes = int.tryParse(snoozeController.text) ?? 5;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('⏰ يرن الآن: ${ringingAlarm.notificationSettings.title}'),
            content: const Text('اختر الإجراء المطلوب:'),
            actions: [
              ElevatedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  await Alarm.set(
                    alarmSettings: ringingAlarm.copyWith(
                      dateTime: now.add(Duration(minutes: snoozeMinutes)),
                    ),
                  );
                  await loadAlarms();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.snooze),
                label: Text('غفوة ($snoozeMinutes د)'),
              ),
              TextButton(
                onPressed: () async {
                  await Alarm.stop(ringingAlarm.id);
                  await loadAlarms();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('إيقاف هذا فقط'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  await Alarm.stopAll();
                  await loadAlarms();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.done_all),
                label: const Text('صحيت! إلغاء كل المتبقي'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مولّد المنبهات المتسلسلة ⏰'),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              ListTile(
                tileColor: Colors.white10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('وقت بداية أول منبه:'),
                trailing: Text(
                  startTime.format(context),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                ),
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: startTime);
                  if (picked != null) setState(() => startTime = picked);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                tileColor: Colors.white10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.music_note, color: Colors.orangeAccent),
                title: const Text('النغمة الموحدة لكل المنبهات:'),
                subtitle: Text(selectedRingtoneName, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: ElevatedButton(
                  onPressed: pickRingtone,
                  child: const Text('اختر نغمة'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد المنبهات (مثلاً 70)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.format_list_numbered),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الفاصل بالدقائق (مثلاً 2)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.timer),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: snoozeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'مدة الغفوة الموحدة لكل المنبهات (بالدقائق)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.snooze),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: isGenerating ? null : generateAlarms,
                      icon: isGenerating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.alarm_add),
                      label: Text(isGenerating ? 'جاري التوليد...' : 'تفعيل السلسلة كاملة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        await Alarm.stopAll();
                        await loadAlarms();
                      },
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('إلغاء الكل'),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                'المنبهات المجدولة حالياً (${activeAlarms.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: activeAlarms.isEmpty
                    ? const Center(child: Text('لا يوجد منبهات مفعلة حالياً'))
                    : ListView.builder(
                        itemCount: activeAlarms.length,
                        itemBuilder: (context, index) {
                          final alarm = activeAlarms[index];
                          final timeStr = TimeOfDay.fromDateTime(alarm.dateTime).format(context);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${alarm.id}')),
                              title: Text('الوقت: $timeStr', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('التاريخ: ${alarm.dateTime.month}/${alarm.dateTime.day}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                onPressed: () async {
                                  await Alarm.stop(alarm.id);
                                  await loadAlarms();
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}