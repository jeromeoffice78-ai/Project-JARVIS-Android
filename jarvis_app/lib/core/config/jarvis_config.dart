class JarvisConfig {
  const JarvisConfig({
    required this.httpBaseUrl,
    required this.wsUrl,
    required this.clientToken,
    required this.printGatewayUrl,
    required this.deviceGatewayUrl,
  });

  final String httpBaseUrl;
  final String wsUrl;
  final String clientToken;
  final String printGatewayUrl;
  final String deviceGatewayUrl;

  factory JarvisConfig.fromEnvironment() {
    return const JarvisConfig(
      httpBaseUrl: String.fromEnvironment(
        'JARVIS_HTTP_BASE',
        defaultValue: 'https://jarvis-legal-enterprise-api.onrender.com',
      ),
      wsUrl: String.fromEnvironment(
        'JARVIS_WS_URL',
        defaultValue: 'wss://jarvis-legal-enterprise-api.onrender.com/ws/jarvis',
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
      deviceGatewayUrl: String.fromEnvironment(
        'JARVIS_DEVICE_GATEWAY_URL',
        defaultValue:
            'https://idpneeyysraraznqmiio.supabase.co/functions/v1/jarvis-device-gateway',
      ),
    );
  }

  bool get hasDevelopmentToken => clientToken.trim().isNotEmpty;
}
