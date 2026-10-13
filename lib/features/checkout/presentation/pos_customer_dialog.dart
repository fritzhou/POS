import 'dart:async';

import 'package:flutter/material.dart';

import '../../catalog/domain/repository_support.dart';
import '../../people/domain/people_models.dart';
import '../../people/domain/people_repository.dart';

class PosCustomerDialog extends StatefulWidget {
  const PosCustomerDialog({
    required this.repository,
    required this.branchId,
    super.key,
  });
  final PeopleRepository repository;
  final String branchId;
  @override
  State<PosCustomerDialog> createState() => _PosCustomerDialogState();
}

class _PosCustomerDialogState extends State<PosCustomerDialog> {
  final _query = TextEditingController();
  Timer? _debounce;
  DataPage<Customer>? _customers;
  bool _loading = false;
  String? _error;
  int _offset = 0;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.listCustomers(
        query: _query.text.trim(),
        active: true,
        branchId: widget.branchId,
        page: PageRequest(offset: _offset, limit: 20),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _customers = result;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error is RepositoryFailure
              ? error.message
              : 'Customers could not be loaded. Check the connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose customer'),
    content: SizedBox(
      width: 480,
      height: MediaQuery.sizeOf(context).height * .5,
      child: Column(
        children: [
          TextField(
            key: const Key('pos-customer-search'),
            controller: _query,
            decoration: const InputDecoration(
              hintText: 'Search customer name or contact',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _offset = 0;
                unawaited(_load());
              });
            },
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                if (!_loading && _customers?.items.isEmpty == true)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No active customers match this search.'),
                  ),
                for (final customer in _customers?.items ?? <Customer>[])
                  ListTile(
                    key: Key('choose-customer-${customer.id}'),
                    title: Text(customer.name),
                    subtitle: customer.phone != null
                        ? Text(customer.phone!)
                        : null,
                    onTap: _loading
                        ? null
                        : () => Navigator.pop(context, customer),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: !_loading && _offset > 0
                    ? () {
                        _offset = (_offset - 20).clamp(0, 100000);
                        unawaited(_load());
                      }
                    : null,
                child: const Text('Previous'),
              ),
              TextButton(
                onPressed: !_loading && _customers?.hasMore == true
                    ? () {
                        _offset = _customers!.nextOffset;
                        unawaited(_load());
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
