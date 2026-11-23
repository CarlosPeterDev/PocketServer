import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n.dart';

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
    name = TextEditingController(text: i?.name ?? tr('My WebDAV drive'));
    user = TextEditingController(text: i?.username ?? 'user');
    pass = TextEditingController(text: i?.password ?? '');
    port = TextEditingController(text: '${i?.port ?? p}');
    folderId = kDefaultFolderId;
    readOnly = i?.readOnly ?? false;
    enabled = i?.enabled ?? true;
    hide = true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? tr('New WebDAV server') : tr('Edit WebDAV server')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                decoration: InputDecoration(labelText: tr('Name')),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null,
              ),
              TextFormField(
                controller: user,
                decoration: InputDecoration(labelText: tr('Username')),
                validator: (v) => (v == null || v.trim().isEmpty || v.contains(':')) ? tr('Required, no ":"') : null,
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
                decoration: InputDecoration(labelText: tr('Port')),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 65535) return '1 - 65535';
                  if (widget.usedPorts.contains(n)) return tr('Port already used');
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Read-only')),
                value: readOnly,
                onChanged: (v) => setState(() => readOnly = v),
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
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}
