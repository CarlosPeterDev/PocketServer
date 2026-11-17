import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class StaticSiteCard extends StatefulWidget {
  const StaticSiteCard({super.key});

  @override
  State<StaticSiteCard> createState() => _StaticSiteCardState();
}

class _StaticSiteCardState extends State<StaticSiteCard> {
  static const _channel = MethodChannel('com.pocketserver.app/static_site');

  String? _address;
  String? _error;
  bool _busy = false;

  Future<void> _changeSite({required bool stop}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final address = await _channel.invokeMethod<String>(
        stop ? 'stop' : 'chooseAndStart',
      );
      if (!mounted) return;
      setState(() {
        if (stop || address != null) _address = address;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'Local hosting is unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = _address;
    final error = _error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local website',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (address != null)
              SelectableText(address)
            else
              const Text(
                'Choose an HTML file up to 1 MiB to open on this device.',
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _changeSite(stop: false),
                  child: Text(
                    address == null ? 'Choose HTML file' : 'Replace HTML file',
                  ),
                ),
                if (address != null)
                  TextButton(
                    onPressed: _busy ? null : () => _changeSite(stop: true),
                    child: const Text('Stop hosting'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
