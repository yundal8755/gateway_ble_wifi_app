import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const GatewayWifiApp());
}

class GatewayWifiApp extends StatelessWidget {
  const GatewayWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gateway WiFi Config',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const WifiConfigScreen(),
    );
  }
}

class WifiConfigScreen extends StatefulWidget {
  const WifiConfigScreen({super.key});

  @override
  State<WifiConfigScreen> createState() => _WifiConfigScreenState();
}

class _WifiConfigScreenState extends State<WifiConfigScreen> {
  BluetoothDevice? selectedDevice;
  List<BluetoothService> _services = [];
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    scanForGateways();
  }

  ///
  /// 1. 게이트웨이 스캔하기
  ///
  void scanForGateways() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName.contains('Ameba') && r.rssi >= -65) {
          setState(() {
            selectedDevice = r.device;
          });
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });
  }

  ///
  /// 2. 게이트웨이 BLE로 연결하기
  ///
  void connectToGateway() async {
    if (selectedDevice == null) return;

    try {
      await selectedDevice!.connect();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to Gateway!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection Error: $e')),
      );
    }
  }

  ///
  /// 3. 게이트웨이에 WiFi 정보 전달하기
  ///
  void sendWifiInfo() async {
    if (selectedDevice == null) return;

    final ssid = ssidController.text;
    final password = passwordController.text;

    // 패킷 생성
    Uint8List packet = prepareWifiInfoPacket(ssid, password);

    print('===== PACKET : $packet =====');
    print('===== SSID: $ssid =====');
    print('===== Password: $password =====');
    print('===== Packet Data: ${packet.toString()} =====');

    try {
      // 서비스 검색
      List<BluetoothService> services =
          await selectedDevice!.discoverServices();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WiFi Info Sent to Gateway!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to find writable characteristic')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// packet 정보 저장하기
  Uint8List prepareWifiInfoPacket(String ssid, String password) {
    Uint8List packet = Uint8List(108);
    packet[0] = 0x00; // 헤더
    packet[1] = 0x03; // 서브명령어
    packet[2] = 0x00; // 예약된 바이트
    packet[3] = 0x68; // 데이터 길이

    List<int> ssidBytes = utf8.encode(ssid.padRight(32, '\x00'));
    packet.setRange(6, 38, ssidBytes);

    List<int> passwordBytes = utf8.encode(password.padRight(32, '\x00'));
    packet.setRange(44, 76, passwordBytes);

    return packet;
  }

  @override
  void dispose() {
    ssidController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gateway WiFi Configuration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ssidController,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: connectToGateway,
              child: const Text('Connect to Gateway'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: sendWifiInfo,
              child: const Text('Send WiFi Info'),
            ),
            const SizedBox(height: 20),
            if (selectedDevice != null)
              Text('Selected Device: ${selectedDevice?.platformName ?? '미정'}'),
            Text('Remote ID Device: ${selectedDevice?.remoteId ?? '미정'}'),
            const SizedBox(height: 20),
            if (_services.isNotEmpty) ...[
              const Text(
                'Discovered Services and Characteristics:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
