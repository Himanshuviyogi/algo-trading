import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../blocs/auth_bloc.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() =>
      _PhoneEntryScreenState();
}

class _PhoneEntryScreenState
    extends State<PhoneEntryScreen>
    with SingleTickerProviderStateMixin {

  final _controller = TextEditingController();

  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    context.read<AuthBloc>().add(
      AuthPhoneSubmitted(
        phoneNumber: "+91${_controller.text.trim()}",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthOtpSent) {
          context.go('/otp-verify');
        }
      },

      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),

        body: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {

            final isLoading =
            state is AuthPhoneSubmitting;

            final errorMessage =
            state is AuthFailure
                ? state.message
                : null;

            return Stack(
              children: [

                /// 🌈 TOP GLOW
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (_, __) {
                    return Positioned(
                      top: -120,
                      right: -80 +
                          (_animationController.value * 40),
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4F46E5)
                              .withOpacity(0.12),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: 90,
                            sigmaY: 90,
                          ),
                          child: Container(),
                        ),
                      ),
                    );
                  },
                ),

                /// 🔥 BOTTOM GLOW
                Positioned(
                  bottom: -100,
                  left: -80,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.cyan.withOpacity(0.08),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 90,
                        sigmaY: 90,
                      ),
                      child: Container(),
                    ),
                  ),
                ),

                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),

                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.center,
                        children: [

                          const SizedBox(height: 20),

                          /// 🔥 LOGO CONTAINER
                          Container(
                            width: 110,
                            height: 110,
                            padding:
                            const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFF4F46E5),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                  const Color(0xFF4F46E5)
                                      .withOpacity(0.25),
                                  blurRadius: 30,
                                  offset:
                                  const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/small_logo.png',
                            ),
                          ),

                          const SizedBox(height: 28),

                          /// TITLE
                          const Text(
                            "Welcome Back",
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                              letterSpacing: -0.5,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            "Enter your mobile number\nto continue",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Colors.black
                                  .withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 40),

                          /// 📱 GLASS INPUT
                          ClipRRect(
                            borderRadius:
                            BorderRadius.circular(22),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: 14,
                                sigmaY: 14,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withOpacity(0.75),
                                  borderRadius:
                                  BorderRadius.circular(
                                    22,
                                  ),
                                  border: Border.all(
                                    color: Colors.white
                                        .withOpacity(0.5),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withOpacity(
                                        0.04,
                                      ),
                                      blurRadius: 20,
                                      offset:
                                      const Offset(0, 8),
                                    ),
                                  ],
                                ),

                                child: Row(
                                  children: [

                                    const SizedBox(width: 18),

                                    /// COUNTRY
                                    Container(
                                      padding:
                                      const EdgeInsets
                                          .symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration:
                                      BoxDecoration(
                                        color: const Color(
                                          0xFFEEF2FF,
                                        ),
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          12,
                                        ),
                                      ),
                                      child: const Text(
                                        "+91",
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                          FontWeight
                                              .w700,
                                          color: Color(
                                            0xFF4338CA,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 14),

                                    Expanded(
                                      child: TextField(
                                        controller:
                                        _controller,
                                        keyboardType:
                                        TextInputType
                                            .number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(
                                            10,
                                          ),
                                        ],
                                        style:
                                        const TextStyle(
                                          fontSize: 17,
                                          fontWeight:
                                          FontWeight
                                              .w600,
                                        ),
                                        decoration:
                                        InputDecoration(
                                          hintText:
                                          "Phone number",
                                          hintStyle:
                                          TextStyle(
                                            color: Colors
                                                .grey
                                                .shade400,
                                            fontSize: 15,
                                          ),
                                          border:
                                          InputBorder
                                              .none,
                                          contentPadding:
                                          const EdgeInsets
                                              .symmetric(
                                            vertical: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          /// ERROR
                          if (errorMessage != null)
                            Container(
                              width: double.infinity,
                              padding:
                              const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius:
                                BorderRadius.circular(
                                  14,
                                ),
                                border: Border.all(
                                  color:
                                  Colors.red.shade100,
                                ),
                              ),
                              child: Row(
                                children: [

                                  Icon(
                                    Icons.error_outline,
                                    color:
                                    Colors.red.shade700,
                                    size: 18,
                                  ),

                                  const SizedBox(width: 8),

                                  Expanded(
                                    child: Text(
                                      errorMessage,
                                      style: TextStyle(
                                        color: Colors
                                            .red.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 34),

                          /// 🚀 BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 60,

                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient:
                                const LinearGradient(
                                  colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF4338CA),
                                  ],
                                ),
                                borderRadius:
                                BorderRadius.circular(
                                  20,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                    const Color(
                                      0xFF4F46E5,
                                    ).withOpacity(0.35),
                                    blurRadius: 22,
                                    offset:
                                    const Offset(0, 10),
                                  ),
                                ],
                              ),

                              child: ElevatedButton(
                                onPressed:
                                isLoading
                                    ? null
                                    : () =>
                                    _submit(context),

                                style:
                                ElevatedButton.styleFrom(
                                  backgroundColor:
                                  Colors.transparent,
                                  shadowColor:
                                  Colors.transparent,
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius
                                        .circular(
                                      20,
                                    ),
                                  ),
                                ),

                                child:
                                isLoading
                                    ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                  CircularProgressIndicator(
                                    strokeWidth:
                                    2.5,
                                    color:
                                    Colors.white,
                                  ),
                                )
                                    : Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment
                                      .center,
                                  children: const [

                                    Text(
                                      "Continue",
                                      style:
                                      TextStyle(
                                        fontSize:
                                        16,
                                        fontWeight:
                                        FontWeight
                                            .w700,
                                        color: Colors
                                            .white,
                                      ),
                                    ),

                                    SizedBox(
                                      width: 8,
                                    ),

                                    Icon(
                                      Icons
                                          .arrow_forward_rounded,
                                      size: 20,
                                      color: Colors
                                          .white,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          /// FOOTER
                          Text(
                            "Secure authentication powered by OTP",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black
                                  .withOpacity(0.38),
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}