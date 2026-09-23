class JarvisConfig {
  const JarvisConfig({
    required this.httpBaseUrl,
    required this.wsUrl,
    required this.clientToken,
    required this.printGatewayUrl,
  });

  final String httpBaseUrl;
  final String wsUrl;
  final String clientToken;
  final String printGatewayUrl;

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
    );
  }

  bool get hasDevelopmentToken => clientToken.trim().isNotEmpty;
}
