class JarvisConfig {
  const JarvisConfig({
    required this.httpBaseUrl,
    required this.wsUrl,
    required this.clientToken,
    required this.printGatewayUrl,
    required this.watchBridgeBaseUrl,
  });

  final String httpBaseUrl;
  final String wsUrl;
  final String clientToken;
  final String printGatewayUrl;
  final String watchBridgeBaseUrl;

  factory JarvisConfig.fromEnvironment() {
    return const JarvisConfig(
      httpBaseUrl: String.fromEnvironment(
        'JARVIS_HTTP_BASE',
        defaultValue: 'http://10.0.2.2:8000',
      ),
      wsUrl: String.fromEnvironment(
        'JARVIS_WS_URL',
        defaultValue: 'ws://10.0.2.2:8000/ws/jarvis',
      ),
      clientToken: String.fromEnvironment(
        'JARVIS_CLIENT_TOKEN',
        defaultValue: '',
      ),
      printGatewayUrl: String.fromEnvironment(
        'JARVIS_PRINT_GATEWAY_URL',
        defaultValue:
            'https://idpneeyysraraznqmiio.supabase.co/functions/v1/jarvis-print-gateway',
      ),
      watchBridgeBaseUrl: String.fromEnvironment(
        'JARVIS_WATCH_BRIDGE_URL',
        defaultValue:
            'https://jarvis-watch-bridge-api.onrender.com',
      ),
    );
  }

  bool get hasDevelopmentToken => clientToken.trim().isNotEmpty;
}
