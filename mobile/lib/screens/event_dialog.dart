import 'package:flutter/material.dart';

import '../models.dart';
import '../services/nyota_service.dart';

/// Lists existing events and lets the user pick one or create a new event.
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

class _EventSheet extends StatefulWidget {
  const _EventSheet();

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  List<NyotaEvent>? _events;
  bool _creating = false;
  final _nameCtrl = TextEditingController();
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
    super.dispose();
  }

  Future<void> _load() async {
    final events = await NyotaService.listEvents();
    if (mounted) setState(() => _events = events);
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _creating ? 'New Event' : 'Choose Event',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (!_creating) ...[
              if (_events == null)
                const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (_events!.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No events yet — create your first one!',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ..._events!.map(
                  (e) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: e.eventDate == null ? null : Text(e.eventDate!),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, e),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(Icons.add),
                label: const Text('Create New Event'),
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
                label: Text(_date == null
                    ? 'Event date (optional)'
                    : _date!.toIso8601String().substring(0, 10)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Event'),
              ),
              TextButton(
                onPressed: () => setState(() => _creating = false),
                child: const Text('Back to events'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
