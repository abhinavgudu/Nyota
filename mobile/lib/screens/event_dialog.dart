import 'package:flutter/material.dart';

import '../models.dart';
import '../services/nyota_service.dart';

/// Lists existing events and lets the user pick, create, or join an event.
/// Returns the selected event, or null if dismissed.
Future<NyotaEvent?> showEventDialog(BuildContext context) async {
  return showModalBottomSheet<NyotaEvent>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _EventSheet(),
  );
}

enum _Mode { choose, create, join }

class _EventSheet extends StatefulWidget {
  const _EventSheet();

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  List<NyotaEvent>? _events;
  _Mode _mode = _Mode.choose;
  final _nameCtrl = TextEditingController();
  final _joinCodeCtrl = TextEditingController();
  DateTime? _date;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _joinCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final events = await NyotaService.listEvents();
      if (mounted) setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _events = []);
    }
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter an event name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final event = await NyotaService.createEvent(
        _nameCtrl.text.trim(),
        _date == null ? null : _date!.toIso8601String().substring(0, 10),
      );
      if (mounted) Navigator.pop(context, event);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not create event. Please try again.';
      });
    }
  }

  Future<void> _join() async {
    final code = _joinCodeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter event code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final event = await NyotaService.joinEventByCode(code);
      if (mounted) Navigator.pop(context, event);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().contains('Invalid')
            ? 'Galat code — sahi event code daalo.'
            : 'Join nahi ho paya. Code check karo.';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      _Mode.choose => 'Choose Event',
      _Mode.create => 'New Event',
      _Mode.join => 'Join Event',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (_mode == _Mode.choose) ...[
              FilledButton.icon(
                onPressed: () => setState(() {
                  _mode = _Mode.join;
                  _error = null;
                }),
                icon: const Icon(Icons.group_add),
                label: const Text('Join by Code / Link'),
              ),
              const SizedBox(height: 12),
              if (_events == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_events!.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No events yet — create or join one!', style: TextStyle(color: Colors.grey)),
                )
              else
                ..._events!.map(
                  (e) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if (e.eventDate != null) e.eventDate!,
                        if (e.joinCode != null) 'Code: ${e.joinCode}',
                      ].join(' • ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, e),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _mode = _Mode.create;
                  _error = null;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Create New Event'),
              ),
            ] else if (_mode == _Mode.join) ...[
              const Text(
                'Event ka 8-character code daalo (jo host ne share kiya hai). Share link se join karne ke liye link open karo.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _joinCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Event code',
                  hintText: 'e.g. A1B2C3D4',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _join,
                child: _busy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Join Event'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _mode = _Mode.choose;
                  _error = null;
                }),
                child: const Text('Back'),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Event name *',
                  hintText: 'e.g. Sharma Wedding Reception',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_date == null ? 'Event date (optional)' : _date!.toIso8601String().substring(0, 10)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Event'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _mode = _Mode.choose;
                  _error = null;
                }),
                child: const Text('Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
