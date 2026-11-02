import 'package:flutter/material.dart';

import '../states/empty_state.dart';
import '../states/error_state.dart';
import 'collection_controller.dart';

class CollectionView<T> extends StatelessWidget {
  const CollectionView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.header,
    this.filterBar,
    this.emptyState,
    this.isGrid = true,
    this.crossAxisCount = 3,
    this.mainAxisSpacing = 4,
    this.crossAxisSpacing = 4,
    this.childAspectRatio = 1.0,
    this.padding = const EdgeInsets.all(4),
  });

  final CollectionController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? header;
  final Widget? filterBar;
  final Widget? emptyState;
  final bool isGrid;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;

        Widget content;
        switch (state.status) {
          case CollectionStatus.loading:
            content = const Center(child: CircularProgressIndicator());
            break;
          case CollectionStatus.error:
            content = ErrorState(
              message: state.errorMessage,
              onRetry: controller.loadInitial,
            );
            break;
          case CollectionStatus.empty:
            content =
                emptyState ??
                EmptyState(
                  kind: state.query.isNotEmpty
                      ? EmptyStateKind.noResults
                      : EmptyStateKind.custom,
                );
            break;
          case CollectionStatus.content:
            content = _buildContent(context, state);
            break;
        }

        return Column(
          children: [
            ?header,
            ?filterBar,
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.loadInitial,
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, CollectionState<T> state) {
    return NotificationListener<ScrollNotification>(
      onNotification: (scroll) {
        if (scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 200) {
          controller.loadMore();
        }
        return false;
      },
      child: isGrid ? _buildGrid(state) : _buildList(state),
    );
  }

  Widget _buildGrid(CollectionState<T> state) {
    final itemCount = state.items.length + (state.isLoadingMore ? 1 : 0);

    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return itemBuilder(context, state.items[index], index);
      },
    );
  }

  Widget _buildList(CollectionState<T> state) {
    final itemCount = state.items.length + (state.isLoadingMore ? 1 : 0);

    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return itemBuilder(context, state.items[index], index);
      },
    );
  }
}
