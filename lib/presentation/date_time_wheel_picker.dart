import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DateTimeWheelPicker extends StatefulWidget {
  const DateTimeWheelPicker({
    super.key,
    required this.initialDateTime,
    this.title = 'Choose date and time',
  });

  final DateTime initialDateTime;
  final String title;

  @override
  State<DateTimeWheelPicker> createState() => _DateTimeWheelPickerState();
}

class _DateTimeWheelPickerState extends State<DateTimeWheelPicker> {
  late final DateTime _firstDate;
  late final DateTime _lastDate;
  late final int _dateCount;
  late final FixedExtentScrollController _dateController;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late DateTime _selectedDate;
  late int _selectedHour;
  late int _selectedMinute;

  @override
  void initState() {
    super.initState();
    final year = widget.initialDateTime.year;
    final currentYear = DateTime.now().year;
    _firstDate = DateTime((year < currentYear ? year : currentYear) - 100);
    _lastDate = DateTime(
      (year > currentYear ? year : currentYear) + 100,
      12,
      31,
    );
    _dateCount = _lastDate.difference(_firstDate).inDays + 1;
    _selectedDate = DateTime(
      widget.initialDateTime.year,
      widget.initialDateTime.month,
      widget.initialDateTime.day,
    );
    _selectedHour = widget.initialDateTime.hour;
    _selectedMinute = widget.initialDateTime.minute;
    _dateController = FixedExtentScrollController(
      initialItem: _selectedDate.difference(_firstDate).inDays,
    );
    _hourController = FixedExtentScrollController(
      initialItem: 24 * 1000 + _selectedHour,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: 60 * 100 + _selectedMinute,
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(onPressed: _finish, child: const Text('Done')),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 264,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: Theme.of(context).brightness,
                    primaryColor: colors.primary,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        color: colors.onSurface,
                        fontSize: 28,
                        height: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: _wheel(
                          context,
                          controller: _dateController,
                          childCount: _dateCount,
                          onSelectedItemChanged: (index) => setState(() {
                            _selectedDate = _firstDate.add(
                              Duration(days: index),
                            );
                          }),
                          itemBuilder: (context, index) {
                            final date = _firstDate.add(Duration(days: index));
                            return Text(
                              _formatWheelDate(date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: CupertinoTheme.of(
                                context,
                              ).textTheme.dateTimePickerTextStyle,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: _wheel(
                          context,
                          controller: _hourController,
                          itemBuilder: (context, index) => Text(
                            _pad(index % 24),
                            textAlign: TextAlign.center,
                            style: CupertinoTheme.of(
                              context,
                            ).textTheme.dateTimePickerTextStyle,
                          ),
                          onSelectedItemChanged: (index) =>
                              setState(() => _selectedHour = index % 24),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          ':',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _wheel(
                          context,
                          controller: _minuteController,
                          itemBuilder: (context, index) => Text(
                            _pad(index % 60),
                            textAlign: TextAlign.center,
                            style: CupertinoTheme.of(
                              context,
                            ).textTheme.dateTimePickerTextStyle,
                          ),
                          onSelectedItemChanged: (index) =>
                              setState(() => _selectedMinute = index % 60),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wheel(
    BuildContext context, {
    required FixedExtentScrollController controller,
    required NullableIndexedWidgetBuilder itemBuilder,
    required ValueChanged<int> onSelectedItemChanged,
    int? childCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 50,
          diameterRatio: 1.8,
          squeeze: 1.12,
          perspective: 0.002,
          useMagnifier: true,
          magnification: 1.05,
          overAndUnderCenterOpacity: 0.48,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onSelectedItemChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: childCount,
            builder: (context, index) {
              final item = itemBuilder(context, index);
              return item == null ? null : Center(child: item);
            },
          ),
        ),
      ],
    );
  }

  void _finish() => Navigator.pop(
    context,
    DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
      _selectedMinute,
    ),
  );
}

String _pad(int value) => value.toString().padLeft(2, '0');

String _formatWheelDate(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
}
