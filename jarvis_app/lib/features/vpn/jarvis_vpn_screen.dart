import 'package:flutter/material.dart';

import 'jarvis_vpn_service.dart';

class JarvisVpnScreen extends StatefulWidget {
  const JarvisVpnScreen({super.key});

  @override
  State<JarvisVpnScreen> createState() =>
      _JarvisVpnScreenState();
}

class _JarvisVpnScreenState
    extends State<JarvisVpnScreen> {
  final JarvisVpnService _service = JarvisVpnService();
  JarvisVpnStatus? _status;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final JarvisVpnStatus status =
          await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    try {
      await _service.openVpnSettings();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open VPN settings: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final JarvisVpnStatus? status = _status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('JARVIS VPN Guard'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh VPN status',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: Icon(
                status?.active == true
                    ? Icons.verified_user
                    : Icons.shield_outlined,
              ),
              title: Text(
                _loading
                    ? 'Checking VPN connection...'
                    : status?.active == true
                        ? 'VPN is active'
                        : 'VPN is not active',
              ),
              subtitle: Text(
                _error != null
                    ? 'Status check failed: $_error'
                    : status == null
                        ? 'No status available.'
                        : 'Transport: ${status.transport} • '
                            'validated: ${status.validated ? 'yes' : 'no'} • '
                            'metered: ${status.metered ? 'yes' : 'no'}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'JARVIS verifies whether Android currently has an active VPN '
                'transport and gives direct access to the system VPN controls. '
                'The encrypted tunnel itself is supplied by the VPN profile or '
                'provider you activate in Android.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.vpn_key),
            label: const Text('Open Android VPN Settings'),
          ),
        ],
      ),
    );
  }
}
