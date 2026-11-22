import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n.dart';

class HubDialog extends StatefulWidget {
  const HubDialog({super.key, this.initial, required this.cfg, required this.usedPorts});
  final WebHubConfig? initial;
  final AppConfig cfg;
  final Set<int> usedPorts;
  @override
  State<HubDialog> createState() => _HubDialogState();
}

class _HubDialogState extends State<HubDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, port;
  late String folderId;
  late bool enabled;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    var p = 2011;
    while (widget.usedPorts.contains(p)) {
      p++;
    }
    name = TextEditingController(text: i?.name ?? tr('Web hub'));
    port = TextEditingController(text: '${i?.port ?? p}');
    folderId = i?.folderId ?? kDefaultFolderId;
    if (folderId != kDefaultFolderId && !widget.cfg.folders.any((f) => f.id == folderId)) {
      folderId = kDefaultFolderId;
    }
    enabled = i?.enabled ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? tr('New web hub') : tr('Edit web hub')),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: name,
              decoration: InputDecoration(labelText: tr('Name')),
              validator: (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null,
            ),
            TextFormField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Port')),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 65535) return '1 - 65535';
                if (widget.usedPorts.contains(n)) return tr('Port already used');
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: folderId,
              decoration: InputDecoration(labelText: tr('Folder')),
              items: [
                DropdownMenuItem(value: kDefaultFolderId, child: Text(tr('App folder'))),
                for (final f in widget.cfg.folders) DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => folderId = v ?? folderId),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Start automatically')),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              WebHubConfig(
                id: widget.initial?.id ?? FtpServerConfig.newId(),
                name: name.text.trim(),
                port: int.parse(port.text),
                folderId: folderId,
                enabled: enabled,
              ),
            );
          },
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}
