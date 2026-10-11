part of 'order_cubit.dart';

sealed class OrderState extends Equatable {
  const OrderState();
}

/// No order action in progress. Initial state when the cubit is created.
class OrderInitial extends OrderState {
  const OrderInitial();

  @override
  List<Object?> get props => [];
}

/// An order is currently being submitted to the price server.
class OrderPlacing extends OrderState {
  const OrderPlacing();

  @override
  List<Object?> get props => [];
}

/// Order was accepted by the price server and written to Firestore.
/// [order] reflects the initial `pending` state; real-time status updates
/// come through the Firestore stream in [OrderRepository].
class OrderPlaced extends OrderState {
  const OrderPlaced(this.order);

  final AlgoOrder order;

  @override
  List<Object?> get props => [order];
}

/// An order action (place or cancel) failed.
/// [message] is user-displayable — it comes from the typed exception thrown
/// by [OrderService] (risk block reason, broker error, network timeout, etc.).
class OrderFailed extends OrderState {
  const OrderFailed(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
