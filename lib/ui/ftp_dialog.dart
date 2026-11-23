import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n.dart';

class FtpDialog extends StatefulWidget {
  const FtpDialog({super.key, this.initial, required this.usedPorts, required this.cfg});
  final AppConfig cfg;
  final FtpServerConfig? initial;
  final Set<int> usedPorts;
  @override
  State<FtpDialog> createState() => _FtpDialogState();
}

class _FtpDialogState extends State<FtpDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, user, pass, port, maxConn, speed;
  late FtpMode mode;
  late bool readOnly, anonymous, enabled, hide;
  late Set<String> folderIds;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    var p = 2121;
    while (widget.usedPorts.contains(p)) {
      p++;
    }
    name = TextEditingController(text: i?.name ?? tr('My FTP server'));
    user = TextEditingController(text: i?.username ?? 'user');
    pass = TextEditingController(text: i?.password ?? '');
    port = TextEditingController(text: '${i?.port ?? p}');
    maxConn = TextEditingController(text: (i?.maxConnections ?? 0) == 0 ? '' : '${i!.maxConnections}');
    speed = TextEditingController(text: (i?.speedLimitKBps ?? 0) == 0 ? '' : '${i!.speedLimitKBps}');
    mode = i?.mode ?? FtpMode.ftp;
    readOnly = i?.readOnly ?? false;
    anonymous = i?.anonymous ?? false;
    enabled = i?.enabled ?? true;
    hide = true;
    folderIds = {kDefaultFolderId};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? tr('New FTP / FTPS server') : tr('Edit server')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                decoration: InputDecoration(labelText: tr('Server name')),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null,
              ),
              TextFormField(
                controller: user,
                decoration: InputDecoration(labelText: tr('Username')),
                validator: (v) => (v == null || v.trim().isEmpty || v.contains(' ')) ? tr('Required, no spaces') : null,
              ),
              TextFormField(
                controller: pass,
                obscureText: hide,
                decoration: InputDecoration(
                  labelText: tr('Password'),
                  suffixIcon: IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => hide = !hide),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? tr('Required') : null,
              ),
              TextFormField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Port'), helperText: tr('Ports under 1024 may need admin rights')),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 65535) return '1 - 65535';
                  if (widget.usedPorts.contains(n)) return tr('Port already used by another server');
                  return null;
                },
              ),
              TextFormField(
                controller: maxConn,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Max connections (empty = 64)')),
                validator: (v) => (v != null && v.isNotEmpty && (int.tryParse(v) ?? 0) < 1) ? tr('Number >= 1') : null,
              ),
              TextFormField(
                controller: speed,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Speed limit per transfer, KB/s (empty = unlimited)')),
                validator: (v) => (v != null && v.isNotEmpty && (int.tryParse(v) ?? 0) < 1) ? tr('Number >= 1') : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FtpMode>(
                initialValue: mode,
                decoration: InputDecoration(labelText: tr('Protocol')),
                items: [for (final m in FtpMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                onChanged: (m) => setState(() => mode = m ?? mode),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Read-only')),
                value: readOnly,
                onChanged: (v) => setState(() => readOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Allow anonymous (read-only)')),
                value: anonymous,
                onChanged: (v) => setState(() => anonymous = v),
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              FtpServerConfig(
                id: widget.initial?.id ?? FtpServerConfig.newId(),
                name: name.text.trim(),
                username: user.text.trim(),
                password: pass.text,
                port: int.parse(port.text),
                mode: mode,
                readOnly: readOnly,
                anonymous: anonymous,
                enabled: enabled,
                folderIds: const [],
                maxConnections: int.tryParse(maxConn.text) ?? 0,
                speedLimitKBps: int.tryParse(speed.text) ?? 0,
              ),
            );
          },
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}
