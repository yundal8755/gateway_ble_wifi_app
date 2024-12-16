import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

void main() {
  runApp(const GatewayWifiApp());
}

///
/// 1. 게이트웨이 스캔 페이지
/// 
class GatewayWifiApp extends StatelessWidget {
  const GatewayWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gateway WiFi Config',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ScanGatewayScreen(),
    );
  }
}

class ScanGatewayScreen extends StatefulWidget {
  const ScanGatewayScreen({super.key});

  @override
  State<ScanGatewayScreen> createState() => _ScanGatewayScreenState();
}

class _ScanGatewayScreenState extends State<ScanGatewayScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isScanComplete = false;

  @override
  void initState() {
    super.initState();
    _scanForGateways();
  }

  /// 게이트웨이를 스캔하는 함수
  Future<void> _scanForGateways() async {
    setState(() {
      _isScanning = true;
      _isScanComplete = false;
      _scanResults = [];
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _scanResults = results
            .where((result) =>
                result.device.platformName.toLowerCase().contains('ameba'))
            .toList();

        if (_scanResults.isNotEmpty) {
          _isScanning = false;
        }
      });
    });

    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    FlutterBluePlus.stopScan();
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _isScanComplete = true;
    });
  }

  /// BLE 기기와 연결하는 함수
  Future<void> _connectToDevice(ScanResult result) async {
    _showLoadingDialog();
    try {
      await result.device.connect();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('게이트웨이 연결에 성공하였습니다!')),
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConfigWifiScreen(selectedDevice: result.device),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection Error: $e')),
      );
    }
  }

  /// 로딩 다이얼로그 표시 함수
  void _showLoadingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );
  }

  /// 스캔 결과를 보여주는 위젯
  Widget _buildBody() {
    if (_isScanning) {
      return const Center(child: Text('기기를 탐색 중입니다...'));
    } else if (_isScanComplete && _scanResults.isEmpty) {
      return const Center(child: Text('기기 탐색이 완료됐습니다.'));
    } else {
      return ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          return ListTile(
            title: Text(result.device.platformName),
            subtitle: Text('${result.device.remoteId}'),
            trailing: ElevatedButton(
              onPressed: () => _connectToDevice(result),
              child: const Text('연결하기'),
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게이트웨이 스캔'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanForGateways,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

///
/// 2. WiFi 정보 입력 페이지
/// 
class ConfigWifiScreen extends StatefulWidget {
  final BluetoothDevice selectedDevice;

  const ConfigWifiScreen({super.key, required this.selectedDevice});

  @override
  State<ConfigWifiScreen> createState() => _ConfigWifiScreenState();
}

class _ConfigWifiScreenState extends State<ConfigWifiScreen> {
  List<WiFiAccessPoint> _wifiNetworks = [];
  WiFiAccessPoint? _selectedWifi;
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _scanForWifiNetworks();
    }
  }

  @override
  void dispose() {
    widget.selectedDevice.disconnect();
    super.dispose();
  }

  /// WiFi 네트워크를 스캔하는 함수
  Future<void> _scanForWifiNetworks() async {
    final canScan = await WiFiScan.instance.canStartScan();
    if (!mounted) return;
    if (canScan == CanStartScan.yes) {
      await WiFiScan.instance.startScan();
      final results = await WiFiScan.instance.getScannedResults();
      if (!mounted) return;
      setState(() {
        _wifiNetworks = results;
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi 스캔을 시작할 수 없습니다.')),
      );
    }
  }

  /// WiFi 정보를 BLE로 전송하는 함수
  Future<void> _sendWifiInfo() async {
    if (_selectedWifi == null || _passwordController.text.isEmpty) return;

    final bool is5Ghz = _selectedWifi!.frequency >= 5000;
    final Uint8List packet = _prepareWifiInfoPacket(
      ssid: _selectedWifi!.ssid,
      bssid: _selectedWifi!.bssid,
      is5Ghz: is5Ghz,
      password: _passwordController.text,
    );

    _showLoadingDialog();
    try {
      List<BluetoothService> services =
          await widget.selectedDevice.discoverServices();
      if (!mounted) return;
      BluetoothCharacteristic? targetCharacteristic;

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            targetCharacteristic = characteristic;
            break;
          }
        }
        if (targetCharacteristic != null) break;
      }

      if (targetCharacteristic != null) {
        await targetCharacteristic.write(packet, withoutResponse: false);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WiFi 정보 전송 성공!')),
        );
      } else {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Writable characteristic not found')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during BLE write operation: $e')),
      );
    }
  }

  /// 로딩 다이얼로그를 표시하는 함수
  void _showLoadingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );
  }

  /// WiFi 정보를 패킷 형태로 준비하는 함수
  Uint8List _prepareWifiInfoPacket({
    required String ssid,
    required String bssid,
    required bool is5Ghz,
    required String password,
  }) {
    Uint8List packet = Uint8List(108);
    packet[0] = 0x00;
    packet[1] = 0x03;
    packet[2] = 0x00;
    packet[3] = 0x68;
    packet[4] = is5Ghz ? 0x01 : 0x00;
    packet[5] = password.isNotEmpty ? 0x01 : 0x00;

    List<int> ssidBytes = utf8.encode(ssid);
    ssidBytes = _padRightWithNull(ssidBytes, 32);
    packet.setRange(6, 38, ssidBytes);

    List<int> bssidBytes = _hexStringToUint8Array(bssid);
    packet.setRange(38, 44, bssidBytes);

    List<int> passwordBytes = utf8.encode(password);
    passwordBytes = _padRightWithNull(passwordBytes, 32);
    packet.setRange(44, 76, passwordBytes);

    debugPrint('================ PACKET DATA ================');
    debugPrint('Packet Length: ${packet.length}');
    debugPrint('Packet Bytes: ${_toHexString(packet)}');
    debugPrint('=============================================');

    return packet;
  }

  /// 리스트를 지정된 길이만큼 0x00으로 패딩하는 함수
  List<int> _padRightWithNull(List<int> original, int length) {
    List<int> padded = List.from(original);
    while (padded.length < length) {
      padded.add(0x00);
    }
    return padded;
  }

  /// BSSID를 Uint8List로 변환하는 함수
  Uint8List _hexStringToUint8Array(String hexString) {
    List<String> hexBytes = hexString.split(":");
    return Uint8List.fromList(
      hexBytes.map((byte) => int.parse(byte, radix: 16)).toList(),
    );
  }

  /// Uint8List를 HEX 문자열로 변환하는 함수
  String _toHexString(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// WiFi 네트워크에 비밀번호가 필요한지 확인하는 함수
  bool _hasPassword(String capabilities) {
    return !(capabilities.toUpperCase().contains("OPEN") ||
        capabilities.isEmpty);
  }

  /// WiFi 비밀번호 입력 다이얼로그를 표시하는 함수
  void _showWifiPasswordDialog(WiFiAccessPoint wifi) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${wifi.ssid} 연결'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '비밀번호 입력',
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendWifiInfo();
              },
              child: const Text('WiFi 정보 보내기'),
            ),
          ],
        );
      },
    );
  }

  /// WiFi 네트워크 목록을 표시하는 위젯
  Widget _buildWifiList() {
    return ListView.separated(
      itemCount: _wifiNetworks.length,
      separatorBuilder: (context, index) => const Divider(
        thickness: 0.5,
        height: 16,
        color: Colors.grey,
      ),
      itemBuilder: (context, index) {
        final wifi = _wifiNetworks[index];
        final frequencyLabel = wifi.frequency >= 5000 ? '5GHz' : '2.4GHz';

        return ListTile(
          title: Text(wifi.ssid),
          subtitle: Text(
            '${wifi.bssid}\n$frequencyLabel\n${_hasPassword(wifi.capabilities) ? '보안 있음' : '보안 없음'}',
            maxLines: 3,
          ),
          trailing: ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedWifi = wifi;
              });
              _showWifiPasswordDialog(wifi);
            },
            child: const Text('연결하기'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi 스캔'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (Platform.isAndroid) const Text('WiFi 네트워크 목록'),
            if (Platform.isAndroid)
              Expanded(
                child: _buildWifiList(),
              ),
          ],
        ),
      ),
    );
  }
}
