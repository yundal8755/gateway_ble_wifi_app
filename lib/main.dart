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

  @override
  void initState() {
    super.initState();
    scanForGateways();
  }

  void scanForGateways() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results
            .where((result) =>
                result.device.platformName.toLowerCase().contains('ameba'))
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('게이트웨이 스캔 결과')),
      body: ListView.builder(
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
                    const SnackBar(content: Text('Connected to Gateway!')),
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
      ),
    );
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
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool is24Ghz = true;
  bool isSecured = true;

  @override
  void initState() {
    super.initState();
    widget.selectedDevice.connectionState
        .listen((BluetoothConnectionState state) {
      print('Connection State: $state');
    });
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
        title: const Text('WiFi 정보 입력 페이지'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WiFi 정보 보내기, BLE 연결 해제
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Uint8List packet = prepareWifiInfoPacket();

                        try {
                          List<BluetoothService> services =
                              await widget.selectedDevice.discoverServices();
                          BluetoothCharacteristic? targetCharacteristic;

                          for (var service in services) {
                            print('Discovered Service UUID: ${service.uuid}');
                            for (var characteristic
                                in service.characteristics) {
                              print(
                                  'Discovered Characteristic UUID: ${characteristic.uuid}');
                              if (characteristic.properties.write) {
                                targetCharacteristic = characteristic;
                                break;
                              }
                            }
                            if (targetCharacteristic != null) {
                              print(
                                  'Target Characteristic UUID Found: ${targetCharacteristic.uuid}');
                              break;
                            }
                          }

                          if (targetCharacteristic != null) {
                            print('Generated Packet: ${packet.toString()}');
                            print(
                                'Generated HEX Packet: ${toHexString(packet)}');

                            await targetCharacteristic.write(packet,
                                withoutResponse: false);
                            print(
                                'Packet successfully written to characteristic: ${targetCharacteristic.uuid}');
                          } else {
                            print('Writable characteristic not found');
                          }
                        } catch (e) {
                          print('Error during BLE write operation: $e');
                        }
                      },
                      child: const Text('WiFi 정보 보내기'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await widget.selectedDevice.disconnect();
                          Navigator.pop(context);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Disconnection Error: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('BLE 연결 해제'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Uint8List prepareWifiInfoPacket() {
    // 고정된 파라미터 상수
    const String ssid = "와이파이 SSID";
    const String password = "와이파이 비밀번호";
    const String bssid = "bssid 값";
    const bool is5Ghz = true;
    const bool isSecured = true;

    // 패킷 전체 길이 : 108바이트
    // packet[0]   = 헤더
    // packet[1]   = 서브명령어(0x03)
    // packet[2]   = 예약된 바이트(0x00)
    // packet[3]   = 데이터 길이(0x68 = 104바이트)
    // 이후 순서 :
    // packet[4]   = 5GHz 여부 (0x01 = true, 0x00 = false)
    // packet[5]   = 보안 여부 (0x01 = true, 0x00 = false)
    // packet[6..37]  = SSID (32바이트, 부족 시 '\x00' 패딩)
    // packet[38..43] = BSSID (6바이트)
    // packet[44..75] = PASSWORD (32바이트, 보안 활성화 시 필요, 부족 시 '\x00' 패딩)

    Uint8List packet = Uint8List(108);

    packet[0] = 0x00; // 헤더
    packet[1] = 0x03; // 서브명령어
    packet[2] = 0x00; // 예약된 바이트
    packet[3] = 0x68; // 데이터 길이 (104바이트)
    packet[4] = is5Ghz ? 0x01 : 0x00;
    packet[5] = isSecured ? 0x01 : 0x00;

    // SSID (최대 32바이트, 길이 모자랄 경우 \x00 패딩)
    List<int> ssidBytes = utf8.encode(ssid);
    if (ssidBytes.length > 32) {
      ssidBytes = ssidBytes.sublist(0, 32);
    }
    ssidBytes = padRightWithNull(ssidBytes, 32);
    packet.setRange(6, 6 + 32, ssidBytes);

    // BSSID (6바이트, "88:36:6c:b7:f9:ae" -> [0x88,0x36,0x6c,0xb7,0xf9,0xae])
    List<int> bssidBytes = hexStringToUint8Array(bssid);
    packet.setRange(38, 38 + 6, bssidBytes);

    // Password (보안 시 32바이트, 부족 시 \x00 패딩)
    List<int> passwordBytes = utf8.encode(password);
    if (passwordBytes.length > 32) {
      passwordBytes = passwordBytes.sublist(0, 32);
    }
    passwordBytes = padRightWithNull(passwordBytes, 32);
    packet.setRange(44, 44 + 32, passwordBytes);

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
}
