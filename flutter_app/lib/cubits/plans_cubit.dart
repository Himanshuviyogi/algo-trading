import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

part 'plans_state.dart';

class PlansCubit extends Cubit<PlansState> {
  PlansCubit({required PlanRepository planRepository})
      : _planRepository = planRepository,
        super(const PlansLoading());

  final PlanRepository _planRepository;

  Future<void> loadPlans({bool forceRefresh = false}) async {
    if (state is! PlansLoaded || forceRefresh) {
      emit(const PlansLoading());
    }
    try {
      final plans = await _planRepository.getPlans(forceRefresh: forceRefresh);
      emit(PlansLoaded(plans));
    } catch (e) {
      emit(PlansError(e.toString()));
    }
  }
}
