import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

void main() {
  runApp(const GatewayWifiApp());
}

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

/// 1. 게이트웨이 스캔 페이지
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
    scanForGateways();
  }

  void scanForGateways() {
    setState(() {
      _isScanning = true;
      _isScanComplete = false;
      _scanResults = [];
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
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

    Future.delayed(const Duration(seconds: 5), () {
      FlutterBluePlus.stopScan();
      setState(() {
        _isScanning = false;
        _isScanComplete = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게이트웨이 스캔'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: scanForGateways,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isScanning) {
      return const Center(child: Text('기기를 탐색 중입니다...'));
    } else if (_isScanComplete && _scanResults.isEmpty) {
      return const Center(child: Text('기기 탐색이 완료됐습니다.'));
    } else {
      return ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          ScanResult result = _scanResults[index];
          return ListTile(
            title: Text(result.device.platformName),
            subtitle: Text('${result.device.remoteId}'),
            trailing: ElevatedButton(
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  },
                );

                try {
                  await result.device.connect();
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('게이트웨이 연결에 성공하였습니다!')),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ConfigWifiScreen(selectedDevice: result.device),
                    ),
                  );
                } catch (e) {
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Connection Error: $e')),
                  );
                }
              },
              child: const Text('연결하기'),
            ),
          );
        },
      );
    }
  }
}

/// 2. WiFi 정보 입력 페이지
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

  void _scanForWifiNetworks() async {
    final canScan = await WiFiScan.instance.canStartScan();
    if (canScan == CanStartScan.yes) {
      await WiFiScan.instance.startScan();
      final results = await WiFiScan.instance.getScannedResults();
      setState(() {
        _wifiNetworks = results;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi 스캔을 시작할 수 없습니다.')),
      );
    }
  }

  void _showLoadingDialog() {
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

  void _sendWifiInfo() async {
    if (_selectedWifi == null || _passwordController.text.isEmpty) return;

    final bool is5Ghz = _selectedWifi!.frequency >= 5000;
    final bool isSecured = _passwordController.text.isNotEmpty;

    // Dialog 표시
    _showLoadingDialog();

    Uint8List packet = prepareWifiInfoPacket(
      ssid: _selectedWifi!.ssid,
      bssid: _selectedWifi!.bssid,
      is5Ghz: is5Ghz,
      password: _passwordController.text,
    );

    // WiFi 정보 콘솔에 출력
    print('SSID: ${_selectedWifi!.ssid}');
    print('BSSID: ${_selectedWifi!.bssid}');
    print('is5Ghz: $is5Ghz');
    print('Password: ${_passwordController.text}');
    print('isSecured : $isSecured');

    try {
      List<BluetoothService> services =
          await widget.selectedDevice.discoverServices();
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
        Navigator.of(context, rootNavigator: true).pop(); // Dialog 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WiFi 정보 전송 성공!')),
        );
      } else {
        Navigator.of(context, rootNavigator: true).pop(); // Dialog 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Writable characteristic not found')),
        );
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop(); // Dialog 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during BLE write operation: $e')),
      );
    }
  }

  @override
  void dispose() {
    widget.selectedDevice.disconnect();
    super.dispose();
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
            if (Platform.isAndroid) ...[
              const Text('WiFi 네트워크 목록'),
              Expanded(
                child: ListView.separated(
                  itemCount: _wifiNetworks.length,
                  separatorBuilder: (context, index) => const Divider(
                    thickness: 0.5, // 구분선 두께
                    height: 16, // 구분선 높이
                    color: Colors.grey, // 구분선 색상
                  ),
                  itemBuilder: (context, index) {
                    final wifi = _wifiNetworks[index];
                    String frequencyLabel =
                        wifi.frequency >= 5000 ? '5GHz' : '2.4GHz';

                    return ListTile(
                      title: Text(wifi.ssid),
                      subtitle: Text(
                        '${wifi.bssid}\n$frequencyLabel\n${hasPassword(wifi.capabilities) ? '보안 있음' : '보안 없음'}',
                        maxLines: 3,
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedWifi = wifi;
                          });

                          // Dialog 표시
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
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
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
                        },
                        child: const Text('연결하기'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Uint8List prepareWifiInfoPacket({
    required String ssid,
    required String bssid,
    required bool is5Ghz,
    required String password,
  }) {
    Uint8List packet = Uint8List(108); // 패킷 길이는 108 바이트로 고정

    // Header
    packet[0] = 0x00; // 헤더
    packet[1] = 0x03; // 명령어
    packet[2] = 0x00; // 예약
    packet[3] = 0x68; // 데이터 길이 (104바이트)

    // Flags
    packet[4] = is5Ghz ? 0x01 : 0x00; 
    packet[5] = password.isNotEmpty ? 0x01 : 0x00; 

    // SSID
    List<int> ssidBytes = utf8.encode(ssid);
    ssidBytes = padRightWithNull(ssidBytes, 32); 
    packet.setRange(6, 38, ssidBytes);

    // BSSID
    List<int> bssidBytes = hexStringToUint8Array(bssid); 
    packet.setRange(38, 44, bssidBytes);

    // Password
    List<int> passwordBytes = utf8.encode(password);
    passwordBytes = padRightWithNull(passwordBytes, 32); 
    packet.setRange(44, 76, passwordBytes);

    print('================ PACKET DATA ================');
    print('Packet Length: ${packet.length}');
    print('Packet Bytes: ${toHexString(packet)}'); // HEX 형태로 출력
    print('=============================================');

    return packet;
  }

  List<int> padRightWithNull(List<int> original, int length) {
    List<int> padded = List.from(original);
    while (padded.length < length) {
      padded.add(0x00);
    }
    return padded;
  }

  Uint8List hexStringToUint8Array(String hexString) {
    // "88:36:6c:b7:f9:ae" -> [0x88,0x36,0x6c,0xb7,0xf9,0xae]
    List<String> hexBytes = hexString.split(":");
    return Uint8List.fromList(
      hexBytes.map((byte) => int.parse(byte, radix: 16)).toList(),
    );
  }

  String toHexString(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  bool hasPassword(String capabilities) {
    // 보안 유형이 OPEN이거나 빈 값이면 비밀번호 없음
    return !(capabilities.toUpperCase().contains("OPEN") ||
        capabilities.isEmpty);
  }
}
