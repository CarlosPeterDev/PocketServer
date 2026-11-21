import 'package:flutter/material.dart';

import '../config.dart';

class FtpDialog extends StatefulWidget {
  const FtpDialog({super.key, this.initial, required this.usedPorts});
  final FtpServerConfig? initial;
  final Set<int> usedPorts;
  @override
  State<FtpDialog> createState() => _FtpDialogState();
}

class _FtpDialogState extends State<FtpDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, user, pass, port;
  late FtpMode mode;
  late bool readOnly, anonymous, enabled, hide;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    var p = 2121;
    while (widget.usedPorts.contains(p)) {
      p++;
    }
    name = TextEditingController(text: i?.name ?? 'My FTP server');
    user = TextEditingController(text: i?.username ?? 'user');
    pass = TextEditingController(text: i?.password ?? '');
    port = TextEditingController(text: '${i?.port ?? p}');
    mode = i?.mode ?? FtpMode.ftp;
    readOnly = i?.readOnly ?? false;
    anonymous = i?.anonymous ?? false;
    enabled = i?.enabled ?? true;
    hide = true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New FTP / FTPS server' : 'Edit server'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Server name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: user,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => (v == null || v.trim().isEmpty || v.contains(' ')) ? 'Required, no spaces' : null,
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
                decoration: const InputDecoration(labelText: 'Port', helperText: 'Ports under 1024 may need admin rights'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 65535) return '1 - 65535';
                  if (widget.usedPorts.contains(n)) return 'Port already used by another server';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FtpMode>(
                value: mode,
                decoration: const InputDecoration(labelText: 'Protocol'),
                items: [for (final m in FtpMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                onChanged: (m) => setState(() => mode = m ?? mode),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Read-only'),
                value: readOnly,
                onChanged: (v) => setState(() => readOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow anonymous (read-only)'),
                value: anonymous,
                onChanged: (v) => setState(() => anonymous = v),
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
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
