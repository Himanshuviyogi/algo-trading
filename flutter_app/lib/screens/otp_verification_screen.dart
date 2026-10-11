import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';
import 'package:flutter/services.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends State<OtpVerificationScreen>
    with SingleTickerProviderStateMixin {

  String verificationId = '';
  String phoneNumber = '';

  int secondsLeft = 60;
  Timer? timer;

  late final AnimationController _animationController;

  final List<TextEditingController> _controllers =
  List.generate(6, (_) => TextEditingController());

  final List<FocusNode> _focusNodes =
  List.generate(6, (_) => FocusNode());

  String get otp =>
      _controllers.map((e) => e.text).join();



  void _handleOtpInput(int index, String value) {
    // Handle paste/autofill
    if (value.length > 1) {
      final otpValue =
      value.replaceAll(RegExp(r'[^0-9]'), '');

      for (int i = 0; i < 6; i++) {
        _controllers[i].text =
        i < otpValue.length ? otpValue[i] : '';
      }

      setState(() {});

      FocusScope.of(context).unfocus();

      if (otpValue.length == 6) {
        Future.delayed(
          const Duration(milliseconds: 200),
          _verifyOtp,
        );
      }

      return;
    }

    setState(() {});

    if (value.isNotEmpty) {
      if (index < 5) {
        FocusScope.of(context).requestFocus(
          _focusNodes[index + 1],
        );
      } else {
        FocusScope.of(context).unfocus();

        if (otp.length == 6) {
          Future.delayed(
            const Duration(milliseconds: 200),
            _verifyOtp,
          );
        }
      }
    } else {
      if (index > 0) {
        FocusScope.of(context).requestFocus(
          _focusNodes[index - 1],
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _initFromBloc();
    _startTimer();
  }

  void _initFromBloc() {
    final state = context.read<AuthBloc>().state;

    if (state is AuthOtpSent) {
      verificationId = state.verificationId;
      phoneNumber = state.phoneNumber;
    }
  }

  void _startTimer() {
    timer?.cancel();

    secondsLeft = 60;

    timer = Timer.periodic(
      const Duration(seconds: 1),
          (t) {
        if (!mounted) return t.cancel();

        if (secondsLeft == 0) {
          t.cancel();
        } else {
          setState(() => secondsLeft--);
        }
      },
    );
  }

  void _verifyOtp() {
    if (otp.length != 6) return;

    context.read<AuthBloc>().add(
      AuthOtpSubmitted(
        verificationId: verificationId,
        smsCode: otp,
        phoneNumber: phoneNumber,
      ),
    );
  }

  void _resendOtp() {
    if (phoneNumber.isEmpty) return;

    _startTimer();

    context.read<AuthBloc>().add(
      AuthResendOtpRequested(
        phoneNumber: phoneNumber,
      ),
    );
  }

  String _errorMessage(String msg) {
    final m = msg.toLowerCase();

    if (m.contains('invalid')) {
      return "Invalid OTP";
    }

    if (m.contains('expired')) {
      return "OTP expired";
    }

    if (m.contains('network')) {
      return "Network error";
    }

    return "Something went wrong";
  }

  @override
  void dispose() {
    timer?.cancel();

    for (var c in _controllers) {
      c.dispose();
    }

    for (var f in _focusNodes) {
      f.dispose();
    }

    _animationController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthOtpSent) {
            verificationId = state.verificationId;
            phoneNumber = state.phoneNumber;
          }
        },

        builder: (context, state) {

          final isLoading =
          state is AuthOtpVerifying;

          final isError =
          state is AuthOtpFailure;

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
                        color: const Color(
                          0xFF4F46E5,
                        ).withOpacity(0.12),
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
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),

                  child: Column(
                    children: [

                      const SizedBox(height: 18),

                      /// 🔙 HEADER
                      Row(
                        children: [

                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },

                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                BorderRadius.circular(
                                  16,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withOpacity(0.04),
                                    blurRadius: 14,
                                    offset:
                                    const Offset(
                                      0,
                                      6,
                                    ),
                                  ),
                                ],
                              ),

                              child: const Icon(
                                Icons
                                    .arrow_back_ios_new_rounded,
                                size: 18,
                              ),
                            ),
                          ),

                          const Spacer(),

                          Container(
                            width: 48,
                            height: 48,
                            padding:
                            const EdgeInsets.all(10),
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
                                16,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                  const Color(
                                    0xFF4F46E5,
                                  ).withOpacity(0.25),
                                  blurRadius: 20,
                                  offset:
                                  const Offset(
                                    0,
                                    8,
                                  ),
                                ),
                              ],
                            ),

                            child: Image.asset(
                              'assets/images/small_logo.png',
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      /// 🔥 TITLE
                      const Text(
                        "OTP Verification",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                          letterSpacing: -0.6,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        "Enter the 6-digit code sent to\n$phoneNumber",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color:
                          Colors.black.withOpacity(0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 44),

                      /// 🔢 OTP BOXES
                      // Row(
                      //   mainAxisAlignment:
                      //   MainAxisAlignment
                      //       .spaceBetween,
                      //
                      //   children: List.generate(
                      //     6,
                      //         (index) {
                      //
                      //       return ClipRRect(
                      //         borderRadius:
                      //         BorderRadius.circular(
                      //           18,
                      //         ),
                      //
                      //         child: BackdropFilter(
                      //           filter: ImageFilter.blur(
                      //             sigmaX: 12,
                      //             sigmaY: 12,
                      //           ),
                      //
                      //           child: Container(
                      //             width: 52,
                      //             height: 64,
                      //             decoration:
                      //             BoxDecoration(
                      //               color: Colors.white
                      //                   .withOpacity(
                      //                 0.75,
                      //               ),
                      //               borderRadius:
                      //               BorderRadius
                      //                   .circular(
                      //                 18,
                      //               ),
                      //               border: Border.all(
                      //                 color: Colors.white
                      //                     .withOpacity(
                      //                   0.55,
                      //                 ),
                      //               ),
                      //               boxShadow: [
                      //                 BoxShadow(
                      //                   color: Colors
                      //                       .black
                      //                       .withOpacity(
                      //                     0.03,
                      //                   ),
                      //                   blurRadius: 14,
                      //                   offset:
                      //                   const Offset(
                      //                     0,
                      //                     6,
                      //                   ),
                      //                 ),
                      //               ],
                      //             ),
                      //
                      //             child: TextField(
                      //               controller:
                      //               _controllers[index],
                      //
                      //               focusNode:
                      //               _focusNodes[index],
                      //
                      //               keyboardType:
                      //               TextInputType
                      //                   .number,
                      //
                      //               textAlign:
                      //               TextAlign.center,
                      //
                      //               maxLength: 1,
                      //
                      //               style:
                      //               const TextStyle(
                      //                 fontSize: 22,
                      //                 fontWeight:
                      //                 FontWeight
                      //                     .w700,
                      //               ),
                      //
                      //               decoration:
                      //               const InputDecoration(
                      //                 counterText: "",
                      //                 border:
                      //                 InputBorder.none,
                      //               ),
                      //
                      //               onChanged: (
                      //                   value,
                      //                   ) {
                      //
                      //                 if (value
                      //                     .isNotEmpty) {
                      //
                      //                   if (index < 5) {
                      //                     FocusScope.of(
                      //                       context,
                      //                     ).requestFocus(
                      //                       _focusNodes[index + 1],
                      //                     );
                      //                   } else {
                      //                     FocusScope.of(
                      //                       context,
                      //                     ).unfocus();
                      //                   }
                      //                 } else {
                      //
                      //                   if (index > 0) {
                      //                     FocusScope.of(
                      //                       context,
                      //                     ).requestFocus(
                      //                       _focusNodes[index - 1],
                      //                     );
                      //                   }
                      //                 }
                      //               },
                      //             ),
                      //           ),
                      //         ),
                      //       );
                      //     },
                      //   ),
                      // ),


                      AutofillGroup(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            6,
                                (index) {
                        
                              final isFocused =
                                  _focusNodes[index].hasFocus;
                        
                              final hasValue =
                                  _controllers[index].text.isNotEmpty;
                        
                              return AnimatedScale(
                                scale: isFocused ? 1.05 : 1,
                                duration: const Duration(milliseconds: 180),
                        
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                        
                                  width: 48,
                                  height: 54,
                        
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.82),
                        
                                    borderRadius:
                                    BorderRadius.circular(18),
                        
                                    border: Border.all(
                                      color: isFocused
                                          ? const Color(0xFF6366F1)
                                          : hasValue
                                          ? const Color(0xFFCBD5E1)
                                          : Colors.white.withOpacity(0.7),
                        
                                      width: isFocused ? 1.8 : 1.2,
                                    ),
                        
                                    boxShadow: [
                        
                                      if (isFocused)
                                        BoxShadow(
                                          color: const Color(0xFF6366F1)
                                              .withOpacity(0.16),
                                          blurRadius: 18,
                                          offset: const Offset(0, 6),
                                        ),
                        
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.035),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                        
                                  child: Center(
                                    // child: TextField(
                                    //   controller: _controllers[index],
                                    //
                                    //   focusNode: _focusNodes[index],
                                    //
                                    //   keyboardType: TextInputType.number,
                                    //
                                    //   textAlign: TextAlign.center,
                                    //
                                    //   maxLength: 1,
                                    //
                                    //   style: const TextStyle(
                                    //     fontSize: 24,
                                    //     fontWeight: FontWeight.w700,
                                    //     color: Color(0xFF111827),
                                    //   ),
                                    //
                                    //   decoration: const InputDecoration(
                                    //     counterText: "",
                                    //     border: InputBorder.none,
                                    //   ),
                                    //
                                    //   cursorColor: Color(0xFF6366F1),
                                    //
                                    //   onChanged: (value) {
                                    //
                                    //     setState(() {});
                                    //
                                    //     if (value.isNotEmpty) {
                                    //
                                    //       if (index < 5) {
                                    //
                                    //         FocusScope.of(context)
                                    //             .requestFocus(
                                    //           _focusNodes[index + 1],
                                    //         );
                                    //
                                    //       } else {
                                    //
                                    //         FocusScope.of(context)
                                    //             .unfocus();
                                    //       }
                                    //
                                    //     } else {
                                    //
                                    //       if (index > 0) {
                                    //
                                    //         FocusScope.of(context)
                                    //             .requestFocus(
                                    //           _focusNodes[index - 1],
                                    //         );
                                    //       }
                                    //     }
                                    //   },
                                    // ),
                        
                                    child: TextField(
                                      controller: _controllers[index],
                        
                                      focusNode: _focusNodes[index],
                        
                                      keyboardType: TextInputType.number,
                        
                                      textAlign: TextAlign.center,
                        
                                      maxLength: index == 0 ? 6 : 1,
                        
                                      autofillHints: const [
                                        AutofillHints.oneTimeCode,
                                      ],
                        
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                        
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                        
                                      decoration: const InputDecoration(
                                        counterText: "",
                                        border: InputBorder.none,
                                      ),
                        
                                      cursorColor: const Color(0xFF6366F1),
                        
                                      onChanged: (value) {
                                        _handleOtpInput(index, value);
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Row(
                      //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      //   children: List.generate(
                      //     6,
                      //         (index) {
                      //
                      //       final isFocused =
                      //           _focusNodes[index].hasFocus;
                      //
                      //       final hasValue =
                      //           _controllers[index].text.isNotEmpty;
                      //
                      //       return AnimatedContainer(
                      //         duration: const Duration(milliseconds: 220),
                      //
                      //         width: 50,
                      //         height: 62,
                      //
                      //         decoration: BoxDecoration(
                      //
                      //           borderRadius:
                      //           BorderRadius.circular(18),
                      //
                      //           gradient: isFocused
                      //               ? const LinearGradient(
                      //             colors: [
                      //               Color(0xFF6366F1),
                      //               Color(0xFF4F46E5),
                      //             ],
                      //           )
                      //               : null,
                      //
                      //           color: isFocused
                      //               ? null
                      //               : Colors.white.withOpacity(0.82),
                      //
                      //           border: Border.all(
                      //             color: isFocused
                      //                 ? Colors.transparent
                      //                 : hasValue
                      //                 ? const Color(0xFF6366F1)
                      //                 .withOpacity(0.35)
                      //                 : Colors.white.withOpacity(0.65),
                      //             width: 1.4,
                      //           ),
                      //
                      //           boxShadow: [
                      //
                      //             if (isFocused)
                      //               BoxShadow(
                      //                 color: const Color(0xFF4F46E5)
                      //                     .withOpacity(0.28),
                      //                 blurRadius: 22,
                      //                 offset: const Offset(0, 8),
                      //               ),
                      //
                      //             BoxShadow(
                      //               color: Colors.black.withOpacity(0.035),
                      //               blurRadius: 10,
                      //               offset: const Offset(0, 4),
                      //             ),
                      //           ],
                      //         ),
                      //
                      //         child: Center(
                      //           child: TextField(
                      //             controller: _controllers[index],
                      //             focusNode: _focusNodes[index],
                      //
                      //             keyboardType: TextInputType.number,
                      //
                      //             textAlign: TextAlign.center,
                      //
                      //             maxLength: 1,
                      //
                      //             style: TextStyle(
                      //               fontSize: 24,
                      //               fontWeight: FontWeight.w700,
                      //               color: isFocused
                      //                   ? Colors.white
                      //                   : const Color(0xFF111827),
                      //             ),
                      //
                      //             decoration: const InputDecoration(
                      //               counterText: "",
                      //               border: InputBorder.none,
                      //             ),
                      //
                      //             cursorColor: Colors.white,
                      //
                      //             onChanged: (value) {
                      //
                      //               setState(() {});
                      //
                      //               if (value.isNotEmpty) {
                      //
                      //                 if (index < 5) {
                      //                   FocusScope.of(context)
                      //                       .requestFocus(
                      //                     _focusNodes[index + 1],
                      //                   );
                      //                 } else {
                      //                   FocusScope.of(context)
                      //                       .unfocus();
                      //                 }
                      //
                      //               } else {
                      //
                      //                 if (index > 0) {
                      //                   FocusScope.of(context)
                      //                       .requestFocus(
                      //                     _focusNodes[index - 1],
                      //                   );
                      //                 }
                      //               }
                      //             },
                      //           ),
                      //         ),
                      //       );
                      //     },
                      //   ),
                      // ),
                      if (isError)
                        Padding(
                          padding:
                          const EdgeInsets.only(
                            top: 16,
                          ),

                          child: Container(
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
                                    _errorMessage(
                                      (
                                          state
                                          as AuthOtpFailure)
                                          .message,
                                    ),

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
                        ),

                      const SizedBox(height: 42),

                      /// 🚀 VERIFY BUTTON
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
                            BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
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
                                : _verifyOtp,

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
                                : const Text(
                              "Verify & Continue",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                FontWeight
                                    .w700,
                                color:
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      /// 🔁 RESEND
                      AnimatedSwitcher(
                        duration:
                        const Duration(
                          milliseconds: 300,
                        ),

                        child: secondsLeft > 0
                            ? Text(
                          "Resend OTP in ${secondsLeft}s",
                          key: ValueKey(secondsLeft),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black
                                .withOpacity(
                              0.45,
                            ),
                            fontWeight:
                            FontWeight.w500,
                          ),
                        )
                            : GestureDetector(
                          onTap: _resendOtp,

                          child: const Text(
                            "Resend OTP",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                              FontWeight.w700,
                              color:
                              Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}