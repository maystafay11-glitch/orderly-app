import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/staff_directory_service.dart';
import 'package:orderly_app/services/staff_session_service.dart';
import 'package:orderly_app/services/worker_web_service.dart';
import 'package:orderly_app/utils/web_photo_capture.dart';

const Color _kGreen = Color(0xFF13795B);
const String _kLastUsernameKey = 'orderly.worker_web.last_username';

class WorkerWebScreen extends StatefulWidget {
  const WorkerWebScreen({super.key, required this.databaseUrl});

  final String databaseUrl;

  @override
  State<WorkerWebScreen> createState() => _WorkerWebScreenState();
}

class _WorkerWebScreenState extends State<WorkerWebScreen> {
  final TextEditingController _restaurantController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _databaseController = TextEditingController();
  WorkerWebService? _service;
  StaffMember? _staff;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  bool _busy = false;
  bool _restoring = true;
  String? _error;
  DateTime? _lastSyncAt;

  bool get _loggedIn => _staff != null && _service != null;

  String get _compiledOrQueryUrl {
    final String compiled = widget.databaseUrl.trim();
    if (compiled.isNotEmpty) return compiled;
    if (kIsWeb) {
      final String fromQuery = Uri.base.queryParameters['db']?.trim() ?? '';
      if (fromQuery.isNotEmpty) return fromQuery;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _usernameController.text = prefs.getString(_kLastUsernameKey) ?? '';
      final String savedUrl = await AppSettings.getFirebaseDatabaseUrl();
      _databaseController.text =
          _compiledOrQueryUrl.isNotEmpty ? _compiledOrQueryUrl : savedUrl;
    } catch (_) {
      // نكمل لشاشة الدخول حتى لو تعذّر التخزين المحلي.
    }

    StaffSession? session;
    try {
      session = await StaffSessionService.restore().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      session = null;
    }
    bool sessionOk = false;
    if (session != null && session.isValid && !session.isManager) {
      try {
        sessionOk = await StaffSessionService.validateSession()
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        sessionOk = false;
      }
    }
    if (session != null && sessionOk) {
      final String url = _resolvedDatabaseUrl();
      if (url.isNotEmpty) {
        _restaurantController.text = session.restaurantId;
        _usernameController.text = session.username;
        _service = WorkerWebService(
          databaseUrl: url,
          restaurantId: session.restaurantId,
        );
        _staff = StaffMember(
          staffId: session.staffId,
          restaurantId: session.restaurantId,
          name: session.name,
          username: session.username,
          role: StaffRole.worker,
          driverPin: session.driverPin,
          pin: session.driverPin,
        );
        _attachLiveSync();
        await _loadOrders();
      } else {
        _restaurantController.text = session.restaurantId;
      }
    }
    if (mounted) setState(() => _restoring = false);
  }

  String _resolvedDatabaseUrl() {
    final String baked = _compiledOrQueryUrl;
    if (baked.isNotEmpty) return baked;
    return _databaseController.text.trim();
  }

  @override
  void dispose() {
    _service?.stopLiveSync();
    _restaurantController.dispose();
    _usernameController.dispose();
    _secretController.dispose();
    _databaseController.dispose();
    super.dispose();
  }

  void _attachLiveSync() {
    _service?.startLiveSync(() {
      unawaited(_loadOrders());
    });
  }

  Future<void> _login() async {
    final String restaurantId = _restaurantController.text.trim();
    if (restaurantId.length < 4 ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(restaurantId)) {
      setState(() => _error =
          'أدخل Restaurant ID صحيحاً من 4 أحرف أو أرقام على الأقل.');
      return;
    }
    final String url = _resolvedDatabaseUrl();
    if (url.isEmpty) {
      setState(() => _error =
          'أدخل رابط Firebase الخاص بالمطعم أو ابنِ النسخة برابط مضمّن.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final WorkerWebService service = WorkerWebService(
      databaseUrl: url,
      restaurantId: restaurantId,
    );
    final StaffAuthResult result = await service.authenticate(
      username: _usernameController.text,
      secret: _secretController.text,
    );
    if (!mounted) return;
    if (!result.success || result.staff == null || !result.staff!.isWorker) {
      setState(() {
        _busy = false;
        _error = result.staff?.isManager == true
            ? 'هذه الواجهة مخصصة للعامل فقط. لوحة المدير غير متاحة هنا.'
            : result.message ?? 'بيانات الدخول غير صحيحة.';
      });
      return;
    }
    await AppSettings.setFirebaseDatabaseUrl(url);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastUsernameKey, _usernameController.text.trim());
    await StaffSessionService.saveSession(StaffSession.fromStaff(result.staff!));
    _service?.stopLiveSync();
    _service = service;
    _staff = result.staff;
    _attachLiveSync();
    await _loadOrders();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _loadOrders() async {
    final StaffMember? staff = _staff;
    final WorkerWebService? service = _service;
    if (staff == null || service == null) return;
    final List<DeliveryOrder> orders = await service.loadOrders(
      driverPin: staff.driverPin,
      driverName: staff.name,
    );
    if (!mounted) return;
    setState(() {
      _orders = orders
        ..sort((DeliveryOrder a, DeliveryOrder b) =>
            b.addedAt.compareTo(a.addedAt));
      _lastSyncAt = DateTime.now();
    });
  }

  Future<void> _logout() async {
    _service?.stopLiveSync();
    await StaffSessionService.clear();
    if (!mounted) return;
    setState(() {
      _staff = null;
      _service = null;
      _orders = <DeliveryOrder>[];
      _secretController.clear();
    });
  }

  Future<void> _showCreateOrder() async {
    final String? created = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _CreateOrderSheet(
        onCreate: (String number, double amount, OrderPaymentType payment,
            String? image) async {
          final WorkerWebService? service = _service;
          final StaffMember? staff = _staff;
          if (service == null || staff == null) return false;
          final bool ok = await service.createOrder(
            driverPin: staff.driverPin,
            driverName: staff.name,
            orderNumber: number,
            amount: amount,
            paymentType: payment,
            proofImageData: image,
          );
          if (ok) await _loadOrders();
          return ok;
        },
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(created)));
    }
  }

  Future<void> _updateStatus(DeliveryOrder order, OrderStatus status) async {
    final WorkerWebService? service = _service;
    final StaffMember? staff = _staff;
    if (service == null || staff == null) return;
    setState(() => _busy = true);
    final bool ok = await service.updateOrderStatus(
      driverPin: staff.driverPin,
      driverName: staff.name,
      orderId: order.id,
      status: status,
    );
    await _loadOrders();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'تم تحديث حالة الطلب ومزامنتها.' : 'تعذر تحديث الطلب.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      body: SafeArea(
        child: _restoring
            ? const Center(child: CircularProgressIndicator(color: _kGreen))
            : _loggedIn
                ? _buildWorkerHome()
                : _buildLogin(),
      ),
    );
  }

  Widget _buildLogin() {
    final bool needUrlField = _compiledOrQueryUrl.isEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.delivery_dining, size: 52, color: _kGreen),
                  const SizedBox(height: 12),
                  const Text(
                    'بوابة العامل',
                    key: ValueKey<String>('worker-web-title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'دخول وإدخال الطلبات فقط — بدون لوحة المدير',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    key: const ValueKey<String>('worker-restaurant-id-field'),
                    controller: _restaurantController,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Restaurant ID',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secretController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور أو PIN',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (needUrlField) ...<Widget>[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _databaseController,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'رابط Firebase',
                        hintText:
                            'https://project-default-rtdb.firebaseio.com',
                        prefixIcon: Icon(Icons.cloud_outlined),
                      ),
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey<String>('worker-login-btn'),
                    onPressed: _busy ? null : _login,
                    icon: const Icon(Icons.login),
                    label: Text(_busy ? 'جار التحقق...' : 'دخول العامل'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkerHome() {
    final StaffMember staff = _staff!;
    final List<DeliveryOrder> active =
        _orders.where((DeliveryOrder o) => o.status.isActive).toList();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.delivery_dining, color: _kGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'مرحباً ${staff.name}',
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _lastSyncAt == null
                          ? 'جاري المزامنة السحابية...'
                          : 'متصل لحظياً · ${staff.restaurantId}',
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _logout,
                tooltip: 'تسجيل الخروج',
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${active.length} نشط · ${_orders.length} الكل',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _showCreateOrder,
                icon: const Icon(Icons.add),
                label: const Text('طلب جديد'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            color: _kGreen,
            onRefresh: _loadOrders,
            child: _orders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const <Widget>[
                      SizedBox(height: 120),
                      Center(child: Text('لا توجد طلبات حالياً')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: _orders.length,
                    itemBuilder: (_, int index) => _OrderCard(
                      order: _orders[index],
                      onPickedUp: () => _updateStatus(
                        _orders[index],
                        OrderStatus.pickedUp,
                      ),
                      onDelivered: () => _updateStatus(
                        _orders[index],
                        OrderStatus.delivered,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onPickedUp,
    required this.onDelivered,
  });

  final DeliveryOrder order;
  final VoidCallback onPickedUp;
  final VoidCallback onDelivered;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'طلب ${order.displayNumber}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
                Text('${order.amount.toStringAsFixed(0)} د.ع'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${order.displayPayment} • ${order.status.label}',
              style: TextStyle(
                color: order.status.color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (order.proofImageData != null) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(order.proofImageData!.split(',').last),
                  height: 110,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (order.status == OrderStatus.preparing) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onPickedUp,
                icon: const Icon(Icons.two_wheeler),
                label: const Text('تم الاستلام من المطعم'),
              ),
            ],
            if (order.status == OrderStatus.pickedUp) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onDelivered,
                icon: const Icon(Icons.done_all),
                label: const Text('تم التسليم للزبون'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateOrderSheet extends StatefulWidget {
  const _CreateOrderSheet({required this.onCreate});

  final Future<bool> Function(
    String,
    double,
    OrderPaymentType,
    String?,
  ) onCreate;

  @override
  State<_CreateOrderSheet> createState() => _CreateOrderSheetState();
}

class _CreateOrderSheetState extends State<_CreateOrderSheet> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  OrderPaymentType _payment = OrderPaymentType.cash;
  String? _image;
  bool _busy = false;
  String? _photoError;

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required bool camera}) async {
    setState(() => _photoError = null);
    Uint8List? bytes = await captureQuickPhoto(preferCamera: camera);
    if (bytes == null || bytes.isEmpty) {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 62,
        maxWidth: 1280,
      );
      if (file != null) bytes = await file.readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) return;
    final Uint8List? compact = _compressProof(bytes);
    if (compact == null) {
      if (mounted) {
        setState(() =>
            _photoError = 'الصورة كبيرة جداً، التقط صورة أقرب بحجم أصغر.');
      }
      return;
    }
    setState(() => _image = 'data:image/jpeg;base64,${base64Encode(compact)}');
  }

  Future<void> _submit() async {
    final double? amount =
        double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_number.text.trim().isEmpty || amount == null || amount < 0) return;
    setState(() => _busy = true);
    final bool ok =
        await widget.onCreate(_number.text, amount, _payment, _image);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, 'تم إرسال الطلب ومزامنته مع تطبيق المدير.');
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'طلب جديد',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'رقم الطلب'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<OrderPaymentType>(
                initialValue: _payment,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                items: OrderPaymentType.values
                    .map(
                      (OrderPaymentType item) => DropdownMenuItem<OrderPaymentType>(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: (OrderPaymentType? value) =>
                    setState(() => _payment = value ?? _payment),
              ),
              const SizedBox(height: 12),
              if (_image != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(_image!.split(',').last),
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _pickPhoto(camera: true),
                      icon: Icon(_image == null
                          ? Icons.photo_camera
                          : Icons.check_circle),
                      label: Text(
                          _image == null ? 'التقاط سريع' : 'إعادة الالتقاط'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pickPhoto(camera: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('المعرض'),
                    ),
                  ),
                ],
              ),
              if (_photoError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_photoError!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send),
                label: Text(_busy ? 'جار الإرسال...' : 'إرسال الطلب'),
              ),
            ],
          ),
        ),
      );
}

Uint8List? _compressProof(Uint8List bytes) {
  try {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return bytes.length > 900000 ? null : bytes;
    }
    img.Image resized = decoded;
    if (decoded.width > 1280) {
      resized = img.copyResize(decoded, width: 1280);
    }
    List<int> jpg = img.encodeJpg(resized, quality: 62);
    if (jpg.length > 900000) {
      jpg = img.encodeJpg(resized, quality: 42);
    }
    if (jpg.length > 900000) return null;
    return Uint8List.fromList(jpg);
  } catch (_) {
    return bytes.length > 900000 ? null : bytes;
  }
}
