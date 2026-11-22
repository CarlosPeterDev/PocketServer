import 'package:flutter/material.dart';

import '../config.dart';

class DavDialog extends StatefulWidget {
  const DavDialog({super.key, this.initial, required this.cfg, required this.usedPorts});
  final DavConfig? initial;
  final AppConfig cfg;
  final Set<int> usedPorts;
  @override
  State<DavDialog> createState() => _DavDialogState();
}

class _DavDialogState extends State<DavDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, user, pass, port;
  late String folderId;
  late bool readOnly, enabled, hide;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    var p = 8080;
    while (widget.usedPorts.contains(p)) {
      p++;
    }
    name = TextEditingController(text: i?.name ?? 'My WebDAV drive');
    user = TextEditingController(text: i?.username ?? 'user');
    pass = TextEditingController(text: i?.password ?? '');
    port = TextEditingController(text: '${i?.port ?? p}');
    folderId = i?.folderId ?? kDefaultFolderId;
    if (folderId != kDefaultFolderId && !widget.cfg.folders.any((f) => f.id == folderId)) folderId = kDefaultFolderId;
    readOnly = i?.readOnly ?? false;
    enabled = i?.enabled ?? true;
    hide = true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New WebDAV server' : 'Edit WebDAV server'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: user,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => (v == null || v.trim().isEmpty || v.contains(':')) ? 'Required, no ":"' : null,
              ),
              TextFormField(
                controller: pass,
                obscureText: hide,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => hide = !hide),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 65535) return '1 - 65535';
                  if (widget.usedPorts.contains(n)) return 'Port already used';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: folderId,
                decoration: const InputDecoration(labelText: 'Folder'),
                items: [
                  const DropdownMenuItem(value: kDefaultFolderId, child: Text('App folder')),
                  for (final f in widget.cfg.folders) DropdownMenuItem(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => folderId = v ?? folderId),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Read-only'),
                value: readOnly,
                onChanged: (v) => setState(() => readOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start automatically'),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              DavConfig(
                id: widget.initial?.id ?? FtpServerConfig.newId(),
                name: name.text.trim(),
                username: user.text.trim(),
                password: pass.text,
                port: int.parse(port.text),
                folderId: folderId,
                readOnly: readOnly,
                enabled: enabled,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
