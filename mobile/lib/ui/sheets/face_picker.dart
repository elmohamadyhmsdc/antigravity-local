import 'package:flutter/material.dart';

import '../atoms/crop.dart';
import '../scaffolds/sheet_scaffold.dart';

class FacePickerOption {
  const FacePickerOption({
    required this.faceId,
    required this.cropPath,
    this.label,
  });

  final int faceId;
  final String cropPath;
  final String? label;
}

class FacePicker {
  FacePicker._();

  static Future<int?> show(
    BuildContext context, {
    required List<FacePickerOption> faces,
    int? selectedFaceId,
    String title = 'Choose Face',
  }) {
    return SheetScaffold.show<int>(
      context: context,
      builder: (_) => SheetScaffold(
        title: title,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: faces.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No faces available'),
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: faces.length,
                  itemBuilder: (context, index) {
                    final face = faces[index];
                    final isSelected = face.faceId == selectedFaceId;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(face.faceId),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CropView(
                                path: face.cropPath,
                                showExpandButton: false,
                              ),
                              if (isSelected)
                                const Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.white,
                                      child: Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
