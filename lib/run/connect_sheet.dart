import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/brick_connection.dart';
import '../services/ev3_transport.dart';

/// Bottom sheet for connecting to an EV3: shows the current connection,
/// lists paired bricks, connects on tap.
Future<void> showConnectSheet(
    BuildContext context, BrickConnection connection) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: connection,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connect to your EV3',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Pair the brick in your device\'s Bluetooth settings first, '
                'then pick it here.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (connection.state == BrickConnectionState.connected)
                ListTile(
                  leading:
                      const Icon(Icons.bluetooth_connected, color: Colors.green),
                  title: Text('Connected to ${connection.deviceName}'),
                  trailing: FilledButton.tonal(
                    key: const Key('disconnect-brick'),
                    onPressed: () async {
                      await connection.disconnect();
                    },
                    child: const Text('Disconnect'),
                  ),
                )
              else
                _DeviceList(connection: connection),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DeviceList extends StatefulWidget {
  const _DeviceList({required this.connection});

  final BrickConnection connection;

  @override
  State<_DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<_DeviceList> {
  late Future<List<Ev3Device>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = widget.connection.scanner!.pairedDevices();
  }

  Future<void> _connect(Ev3Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    debugPrint('[BrickLogic] connecting to ${device.name} (${device.address})…');
    try {
      await widget.connection.connect(device);
      debugPrint('[BrickLogic] connected to ${device.name}');
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text('Connected to ${device.name}!')));
    } catch (e, stack) {
      // Surface the real reason (errno text from the transport) both on
      // screen and to the console/DevTools log, so it can be copied.
      final detail = e is SocketException ? e.message : '$e';
      debugPrint('[BrickLogic] connect FAILED: $detail');
      debugPrintStack(stackTrace: stack, label: '[BrickLogic] connect error');
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text("Couldn't connect to ${device.name}: $detail"),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connecting =
        widget.connection.state == BrickConnectionState.connecting;
    return FutureBuilder<List<Ev3Device>>(
      future: _devices,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final devices = snapshot.data!;
        if (devices.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No paired Bluetooth devices found.'),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final device in devices)
              ListTile(
                key: Key('device-${device.address}'),
                leading: const Icon(Icons.bluetooth),
                title: Text(device.name),
                subtitle: Text(device.address),
                trailing: connecting &&
                        widget.connection.deviceName == device.name
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                enabled: !connecting,
                onTap: () => _connect(device),
              ),
          ],
        );
      },
    );
  }
}
