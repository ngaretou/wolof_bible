import 'package:fluent_ui/fluent_ui.dart';

class ColumnHeader extends StatelessWidget {
  final List<Widget> leadingControls;
  final List<Widget>? trailingControls;
  final VoidCallback onFontIncrease;
  final VoidCallback onFontDecrease;
  final bool isLinked;
  final ValueChanged<bool> onLinkChanged;
  final VoidCallback onDelete;
  final bool canDelete;

  const ColumnHeader({
    super.key,
    required this.leadingControls,
    this.trailingControls,
    required this.onFontIncrease,
    required this.onFontDecrease,
    required this.isLinked,
    required this.onLinkChanged,
    required this.onDelete,
    this.canDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      //Each column has 5 above and then 2.5 l and r,
      //which when beside each other makes 5 between each col.
      //Padding in bible view makes the first and last column have the full 5.
      padding: const EdgeInsets.only(top: 5.0, right: 2.5, left: 2.5),
      child: Card(
        //The default card color is good for dark but for white it's basically just white, so to differentiate soften a bit with grey
        backgroundColor: FluentTheme.of(context).brightness == Brightness.dark
            ? null
            : FluentTheme.of(context).cardColor.lerpWith(Colors.grey, .1),
        padding: const EdgeInsets.only(top: 12, bottom: 12, left: 6, right: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Wrap(
                    //space betwen items
                    spacing: 5,
                    //space between rows when stacked
                    runSpacing: 8,
                    direction: Axis.horizontal,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.start,
                    children: [
                      ...leadingControls,
                      //Grouping for the buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          //Font increase/decrease
                          Button(
                            onPressed: onFontIncrease,
                            child: const Icon(FluentIcons.font_increase),
                          ),
                          const SizedBox(width: 5),
                          Button(
                            onPressed: onFontDecrease,
                            child: const Icon(FluentIcons.font_decrease),
                          ),
                          const SizedBox(width: 10),

                          ToggleButton(
                            checked: isLinked,
                            onChanged: onLinkChanged,
                            child: const Icon(FluentIcons.link),
                          ),
                        ],
                      ),
                      ...trailingControls ?? [],
                    ],
                  ),
                ],
              ),
            ),

            //If this is column 1, don't let the user delete the column
            if (canDelete)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(FluentIcons.calculator_multiply),
              ),
            if (!canDelete) const SizedBox(width: 30),
          ],
        ),
      ),
    );
  }
}
