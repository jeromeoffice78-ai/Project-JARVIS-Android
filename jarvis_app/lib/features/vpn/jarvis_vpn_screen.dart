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
  final TextEditingController _server = TextEditingController();
  final TextEditingController _identity = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _psk = TextEditingController();
  JarvisVpnStatus? _status;
  bool _platformSupported = false;
  bool _warpInstalled = false;
  String _authentication = 'usernamePassword';
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _server.dispose();
    _identity.dispose();
    _username.dispose();
    _password.dispose();
    _psk.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final JarvisVpnStatus status =
          await _service.getStatus();
      final Map<Object?, Object?> support =
          await _service.getPlatformSupport();
      final Map<Object?, Object?> warp =
          await _service.getWarpStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _platformSupported = support['supported'] == true;
        _warpInstalled = warp['installed'] == true;
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

  Future<void> _openWarp() async {
    try {
      await _service.openWarp();
    } on Object catch (error) {
      _showMessage('Unable to open Cloudflare WARP: $error');
    }
  }

  Future<void> _provisionAndConnect() async {
    if (_server.text.trim().isEmpty || _identity.text.trim().isEmpty) {
      _showMessage('Enter the VPN server and IKE identity.');
      return;
    }
    setState(() => _loading = true);
    try {
      final bool consented = await _service.provisionIkev2(
        server: _server.text,
        identity: _identity.text,
        authentication: _authentication,
        username: _username.text,
        password: _password.text,
        preSharedKey: _psk.text,
      );
      if (!consented) throw StateError('VPN permission was not granted.');
      await _service.startProvisionedVpn();
      _password.clear();
      _psk.clear();
      _showMessage('Encrypted IKEv2 VPN connection requested.');
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _loading = false);
      _showMessage('Unable to connect VPN: $error');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _service.stopProvisionedVpn();
      _showMessage('VPN disconnected.');
      await _refresh();
    } on Object catch (error) {
      _showMessage('Unable to disconnect VPN: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.cloud_done_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cloudflare WARP',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Chip(
                        label: Text(
                          _warpInstalled ? 'Installed' : 'Not installed',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status?.active == true
                        ? 'Android reports an active VPN connection. Open Cloudflare WARP to verify its switch shows Connected.'
                        : 'Cloudflare encrypted protection. Install or open Cloudflare WARP or One Agent, accept Android VPN permission, and switch it to Connected.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _openWarp,
                    icon: Icon(
                      _warpInstalled ? Icons.open_in_new : Icons.download,
                    ),
                    label: Text(
                      _warpInstalled
                          ? 'Open Cloudflare WARP'
                          : 'Install Cloudflare WARP',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.security),
                    label: const Text('Verify VPN Protection'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Encrypted IKEv2/IPsec tunnel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _platformSupported
                        ? 'Configure your VPN server. Android securely manages the encrypted tunnel.'
                        : 'A real tunnel requires Android 11+ with IPsec tunnel support.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _server,
                    enabled: _platformSupported && !_loading,
                    decoration: const InputDecoration(
                      labelText: 'VPN server hostname or IP',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _identity,
                    enabled: _platformSupported && !_loading,
                    decoration: const InputDecoration(
                      labelText: 'IKE identity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _authentication,
                    decoration: const InputDecoration(
                      labelText: 'Authentication',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: 'usernamePassword',
                        child: Text('Username and password'),
                      ),
                      DropdownMenuItem(
                        value: 'psk',
                        child: Text('Pre-shared key'),
                      ),
                    ],
                    onChanged: !_platformSupported || _loading
                        ? null
                        : (String? value) => setState(
                              () => _authentication = value ?? 'usernamePassword',
                            ),
                  ),
                  const SizedBox(height: 10),
                  if (_authentication == 'usernamePassword') ...<Widget>[
                    TextField(
                      controller: _username,
                      enabled: _platformSupported && !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enabled: _platformSupported && !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else
                    TextField(
                      controller: _psk,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enabled: _platformSupported && !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Pre-shared key',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _platformSupported && !_loading
                        ? _provisionAndConnect
                        : null,
                    icon: const Icon(Icons.lock),
                    label: const Text('Create and Connect VPN'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  ),
                ],
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
