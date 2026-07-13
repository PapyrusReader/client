import 'package:flutter/material.dart';
import 'package:papyrus/acquisition/acquisition_api_client.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:provider/provider.dart';

class AcquisitionPage extends StatefulWidget {
  const AcquisitionPage({super.key});

  @override
  State<AcquisitionPage> createState() => _AcquisitionPageState();
}

class _AcquisitionPageState extends State<AcquisitionPage> {
  final _queryController = TextEditingController();
  List<AcquisitionEndpoint> _endpoints = [];
  List<TorrentRelease> _releases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEndpoints();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  AcquisitionApiClient get _client => AcquisitionApiClient(
    config: context.read<SyncSettingsProvider>().activeApiConfig,
  );

  String? get _token => context.read<AuthProvider>().accessToken;

  Future<void> _loadEndpoints() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to manage acquisition integrations.';
      });
      return;
    }
    try {
      final endpoints = await _client.listEndpoints(token);
      if (mounted) setState(() => _endpoints = endpoints);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load acquisition integrations.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final token = _token;
    final query = _queryController.text.trim();
    if (token == null || query.isEmpty) return;
    setState(() => _loading = true);
    try {
      final releases = await _client.search(accessToken: token, query: query);
      if (mounted) setState(() => _releases = releases);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Search failed. Check the configured indexers.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addEndpoint() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final apiKey = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    var kind = AcquisitionEndpointKind.qbittorrent;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add integration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              DropdownButtonFormField(
                initialValue: kind,
                items: AcquisitionEndpointKind.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => kind = value ?? kind,
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'Server URL'),
              ),
              TextField(
                controller: apiKey,
                decoration: const InputDecoration(
                  labelText: 'API key (if applicable)',
                ),
              ),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: 'Username (if applicable)',
                ),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password (if applicable)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final token = _token;
              final baseUrl = Uri.tryParse(url.text.trim());
              if (token == null ||
                  name.text.trim().isEmpty ||
                  baseUrl == null ||
                  !baseUrl.hasScheme)
                return;
              try {
                await _client.createEndpoint(
                  accessToken: token,
                  name: name.text.trim(),
                  kind: kind,
                  baseUrl: baseUrl,
                  apiKey: apiKey.text.trim().isEmpty
                      ? null
                      : apiKey.text.trim(),
                  username: username.text.trim().isEmpty
                      ? null
                      : username.text.trim(),
                  password: password.text.isEmpty ? null : password.text,
                );
                if (context.mounted) Navigator.pop(context, true);
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not save this integration.'),
                    ),
                  );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    url.dispose();
    apiKey.dispose();
    username.dispose();
    password.dispose();
    if (submitted == true) _loadEndpoints();
  }

  @override
  Widget build(BuildContext context) {
    final downloadClients = _endpoints.where(
      (endpoint) => const {
        AcquisitionEndpointKind.qbittorrent,
        AcquisitionEndpointKind.transmission,
        AcquisitionEndpointKind.deluge,
      }.contains(endpoint.kind),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Acquisition')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEndpoint,
        icon: const Icon(Icons.add),
        label: const Text('Integration'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadEndpoints,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Torrent & automation',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure indexers, download clients, and Readarr or other Arr applications.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _queryController,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Search releases',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ..._endpoints.map(
              (endpoint) => Card(
                child: ListTile(
                  leading: Icon(_iconFor(endpoint.kind)),
                  title: Text(endpoint.name),
                  subtitle: Text(
                    '${endpoint.kind.name} • ${endpoint.baseUrl.host}',
                  ),
                  trailing: endpoint.enabled
                      ? const Icon(Icons.check_circle_outline)
                      : const Icon(Icons.pause_circle_outline),
                ),
              ),
            ),
            if (_releases.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20, bottom: 8),
                child: Text('Results'),
              ),
            ..._releases.map(
              (release) => Card(
                child: ListTile(
                  title: Text(release.title),
                  subtitle: Text(
                    '${release.indexer}${release.seeders == null ? '' : ' • ${release.seeders} seeders'}',
                  ),
                  trailing: PopupMenuButton<AcquisitionEndpoint>(
                    itemBuilder: (_) => downloadClients
                        .map(
                          (client) => PopupMenuItem(
                            value: client,
                            child: Text('Send to ${client.name}'),
                          ),
                        )
                        .toList(),
                    onSelected: (client) async {
                      final token = _token;
                      if (token == null) return;
                      await _client.submitRelease(
                        accessToken: token,
                        endpointId: client.id,
                        release: release,
                      );
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Release submitted.')),
                        );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(AcquisitionEndpointKind kind) => switch (kind) {
    AcquisitionEndpointKind.qbittorrent ||
    AcquisitionEndpointKind.transmission ||
    AcquisitionEndpointKind.deluge => Icons.downloading_outlined,
    AcquisitionEndpointKind.prowlarr ||
    AcquisitionEndpointKind.torznab ||
    AcquisitionEndpointKind.newznab => Icons.travel_explore,
    _ => Icons.auto_awesome_motion_outlined,
  };
}
