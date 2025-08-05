import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sliding_up_panel/flutter_sliding_up_panel.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:photo_gallery/photo_gallery.dart';
import 'package:file_picker/file_picker.dart';
// import 'package:whatsapp_camera/camera/view_image.dart';

class _WhatsAppCameraController extends ChangeNotifier {
  ///
  /// don't necessary to use this class
  /// this is the class to controller the actions
  ///
  _WhatsAppCameraController({this.multiple = true});

  /// permission to select multiple images
  ///
  /// multiple => default is true
  ///
  ///
  ///
  final bool multiple;
  final selectedImages = <File>[];
  // var images = <Medium>[];

  Future<bool> handlerPermissions() async {
    final status = await Permission.storage.request();
    if (Platform.isIOS) {
      await Permission.photos.request();
      await Permission.mediaLibrary.request();
    }
    return status.isGranted;
  }

  bool imageIsSelected(String? fileName) {
    final index =
        selectedImages.indexWhere((e) => e.path.split('/').last == fileName);
    return index != -1;
  }

  // _timer() {
  //   Timer.periodic(const Duration(seconds: 2), (t) async {
  //     Permission.camera.isGranted.then((value) {
  //       if (value) {
  //         getPhotosToGallery();
  //         t.cancel();
  //       }
  //     });
  //   });
  // }

  // Future<void> getPhotosToGallery() async {
  //   final permission = await handlerPermissions();
  //   if (permission) {
  //     final albums = await PhotoGallery.listAlbums(
  //       mediumType: MediumType.image,
  //     );
  //     final res = await Future.wait(albums.map((e) => e.listMedia()));
  //     final index = res.indexWhere((e) => e.album.name == 'All');
  //     if (index != -1) images.addAll(res[index].items);
  //     if (index == -1) {
  //       for (var e in res) {
  //         images.addAll(e.items);
  //       }
  //     }
  //     notifyListeners();
  //   }
  // }

  // Future<void> inicialize() async {
  //   _timer();
  // }

  Future<void> openGallery() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: multiple,
      type: FileType.image,
      // compressionQuality: 0,
    );
    if (res != null) {
      for (var element in res.files) {
        if (element.path != null) selectedImages.add(File(element.path!));
      }
    }
  }

  void captureImage(File file) {
    ImageGallerySaverPlus.saveFile(file.path);
    selectedImages.add(file);
  }

  // Future<void> selectImage(Medium image) async {
  //   if (multiple) {
  //     final index = selectedImages
  //         .indexWhere((e) => e.path.split('/').last == image.filename);
  //     if (index != -1) {
  //       selectedImages.removeAt(index);
  //     } else {
  //       final file = await image.getFile();
  //       selectedImages.add(file);
  //     }
  //   } else {
  //     selectedImages.clear();
  //     final file = await image.getFile();
  //     selectedImages.add(file);
  //   }
  //   notifyListeners();
  // }
}

class WhatsappCamera extends StatefulWidget {
  /// permission to select multiple images
  ///
  /// multiple => default is true
  ///
  ///
  ///how use:
  ///```dart
  ///List<File>? res = await Navigator.push(
  /// context,
  /// MaterialPageRoute(
  ///   builder: (context) => const WhatsappCamera()),
  ///);
  ///
  ///```
  ///
  final bool multiple;

  /// how use:
  ///```dart
  ///List<File>? res = await Navigator.push(
  /// context,
  /// MaterialPageRoute(
  ///   builder: (context) => const WhatsappCamera()),
  ///);
  ///
  ///```
  ///
  const WhatsappCamera({super.key, this.multiple = false});

  @override
  State<WhatsappCamera> createState() => _WhatsappCameraState();
}

class _WhatsappCameraState extends State<WhatsappCamera>
    with WidgetsBindingObserver {
  late _WhatsAppCameraController controller;
  final painel = SlidingUpPanelController();
  MediaCapture? _mediaCapture;
  StreamSubscription<MediaCapture?>? _subscription;
  late bool _hasFrontCamera;
  CameraAspectRatios _currentAspectRatio = CameraAspectRatios.ratio_4_3;
  double get _currentAspectRatioValue {
    if (_currentAspectRatio == CameraAspectRatios.ratio_4_3) {
      return 4.0 / 3.0;
    } else if (_currentAspectRatio == CameraAspectRatios.ratio_1_1) {
      return 1.0 / 1.0;
    } else {
      return 16.0 / 9.0;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    painel.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    controller = _WhatsAppCameraController(multiple: widget.multiple);
    painel.addListener(() {
      if (painel.status.name == 'hidden') {
        controller.selectedImages.clear();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // controller.inicialize();
      _hasFrontCamera = await hasFrontCamera();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: CameraAwesomeBuilder.awesome(
          saveConfig: SaveConfig.photo(),
          sensorConfig: SensorConfig.single(
            sensor: Sensor.position(SensorPosition.back),
            aspectRatio: _currentAspectRatio,
          ),
          previewFit: CameraPreviewFit.contain,
          // previewAlignment: Alignment.center,
          previewDecoratorBuilder: (state, preview) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final finalPreviewHeight = screenWidth * _currentAspectRatioValue;
            final offsetHeight = (screenHeight - finalPreviewHeight) * 0.5;
            if (offsetHeight < 0) {
              return const SizedBox();
            }
            debugPrint(
                "========${preview.previewSize.toString()}, ${preview.rect.toString()}, ${preview.nativePreviewSize.toString()}");
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: offsetHeight,
                    color: Colors.black,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: offsetHeight,
                    color: Colors.black,
                  ),
                ),
              ],
            );
          },
          theme: AwesomeTheme(
            bottomActionsBackgroundColor: Colors.transparent,
            buttonTheme: AwesomeButtonTheme(
              backgroundColor: Colors.black.withOpacity(0.5),
              iconSize: 20,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),

              // Tap visual feedback (ripple, bounce...)
              buttonBuilder: (child, onTap) {
                return ClipOval(
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.cyan.withOpacity(0.5),
                      onTap: onTap,
                      child: child,
                    ),
                  ),
                );
              },
            ),
          ),
          topActionsBuilder: (state) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AwesomeOrientedWidget(
                  rotateWithDevice: true,
                  child: IconButton(
                    color: Colors.white,
                    onPressed: (() => Navigator.pop(context)),
                    icon: const Icon(Icons.close),
                  ),
                ),
                // (state is PhotoCameraState)
                //     ? AwesomeAspectRatioButton(
                //         state: state,
                //         onAspectRatioTap: (sensorConfig, aspectRatio) {
                //           sensorConfig.switchCameraRatio();
                //           if (aspectRatio == CameraAspectRatios.ratio_16_9) {
                //             // setAspectRatio(CameraAspectRatios.ratio_4_3);
                //             setState(() {
                //               _currentAspectRatio =
                //                   CameraAspectRatios.ratio_4_3;
                //             });
                //           } else if (aspectRatio ==
                //               CameraAspectRatios.ratio_4_3) {
                //             // setAspectRatio(CameraAspectRatios.ratio_1_1);
                //             setState(() {
                //               _currentAspectRatio =
                //                   CameraAspectRatios.ratio_1_1;
                //             });
                //           } else {
                //             // setAspectRatio(CameraAspectRatios.ratio_16_9);
                //             setState(() {
                //               _currentAspectRatio =
                //                   CameraAspectRatios.ratio_16_9;
                //             });
                //           }
                //           debugPrint("${sensorConfig.aspectRatio.toString()}");
                //           // state.switchCameraSensor(
                //           //   aspectRatio: CameraAspectRatios.ratio_1_1,
                //           // );
                //         },
                //       )
                //     : const SizedBox(),
                AwesomeOrientedWidget(
                  rotateWithDevice: true,
                  child: IconButton(
                    color: Colors.white,
                    onPressed: () async {
                      controller.openGallery().then((value) {
                        if (controller.selectedImages.isNotEmpty) {
                          Navigator.pop(context, controller.selectedImages);
                        }
                      });
                    },
                    icon: const Icon(Icons.image),
                  ),
                ),
              ],
            ),
          ),
          middleContentBuilder: (state) => const SizedBox(),
          bottomActionsBuilder: (state) {
            _subscription ??=
                state.captureState$.listen((MediaCapture? mediaCapture) {
              if (_mediaCapture == mediaCapture) return;
              _mediaCapture = mediaCapture;
              if (mediaCapture != null &&
                  mediaCapture.status == MediaCaptureStatus.success) {
                controller.captureImage(File(filePath(mediaCapture)));
                Navigator.pop(context, controller.selectedImages);
              }
            });

            return AwesomeBottomActions(
              state: state,
              left: AwesomeFlashButton(
                state: state,
              ),
              right: _hasFrontCamera
                  ? AwesomeCameraSwitchButton(
                      state: state,
                      scale: 1.0,
                      onSwitchTap: (state) {
                        state.switchCameraSensor(
                          aspectRatio: state.sensorConfig.aspectRatio,
                        );
                      },
                    )
                  : null,
            );
          },
        ),
        // CameraCamera(
        //   enableZoom: false,
        //   resolutionPreset: ResolutionPreset.high,
        //   onFile: (file) {
        //     controller.captureImage(file);
        //     Navigator.pop(context, controller.selectedImages);
        //   },
        // ),
      ),
    );
  }

  String filePath(MediaCapture mediaCapture) {
    if (mediaCapture.status == MediaCaptureStatus.success) {
      return mediaCapture.captureRequest.when(
        single: (single) => single.file!.path,
        multiple: (multiple) => multiple.fileBySensor.values.first!.path,
      );
    } else {
      return "null found";
    }
  }

  Future<bool> hasFrontCamera() async {
    // 初始化相机
    WidgetsFlutterBinding.ensureInitialized();
    List<CameraDescription> cameras = await availableCameras();

    // 检查是否有前置摄像头
    for (var camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        return true; // 存在前置摄像头
      }
    }

    return false; // 不存在前置摄像头
  }
}

// class _ImagesPage extends StatefulWidget {
//   final _WhatsAppCameraController controller;

//   ///
//   /// close action
//   /// how use:
//   /// ```dart
//   /// close: () {
//   ///   //pop painel
//   /// }
//   /// ```
//   ///
//   final void Function()? close;

//   ///
//   /// done action
//   /// how use:
//   /// ```dart
//   /// done: () {
//   ///   //send images
//   /// }
//   /// ```
//   ///
//   final void Function()? done;

//   ///
//   ///
//   /// this is thi page of swipe to up
//   /// and show the images of gallery
//   /// don`t is necessary your implementation by the final programmer
//   ///
//   ///
//   const _ImagesPage({
//     required this.controller,
//     required this.close,
//     required this.done,
//   });

//   @override
//   State<_ImagesPage> createState() => __ImagesPageState();
// }

// class __ImagesPageState extends State<_ImagesPage> {
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       color: Colors.black,
//       height: MediaQuery.of(context).size.height - 40,
//       child: Column(
//         children: [
//           Container(
//             height: 40,
//             decoration: const BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.only(
//                   topLeft: Radius.circular(15),
//                   topRight: Radius.circular(15),
//                 )),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 IconButton(
//                   onPressed: widget.close?.call,
//                   icon: const Icon(Icons.close),
//                 ),
//                 if (widget.controller.multiple)
//                   Text(widget.controller.selectedImages.length.toString()),
//                 IconButton(
//                   onPressed: widget.done?.call,
//                   icon: const Icon(Icons.check),
//                 )
//               ],
//             ),
//           ),
//           Expanded(
//             child: GridView.builder(
//               padding: const EdgeInsets.symmetric(horizontal: 5),
//               itemCount: widget.controller.images.length,
//               physics: const BouncingScrollPhysics(),
//               gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 3,
//                 mainAxisExtent: 140,
//                 crossAxisSpacing: 5,
//                 mainAxisSpacing: 5,
//                 childAspectRatio: MediaQuery.of(context).size.width /
//                     (MediaQuery.of(context).size.height / 4),
//               ),
//               itemBuilder: (context, index) {
//                 return InkWell(
//                   onTap: () => widget.controller
//                       .selectImage(widget.controller.images[index]),
//                   child: _ImageItem(
//                     selected: widget.controller.imageIsSelected(
//                       widget.controller.images[index].filename,
//                     ),
//                     image: widget.controller.images[index],
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ImageItem extends StatelessWidget {
//   ///
//   /// medium image
//   /// is formatter usage for package: photo_gallery
//   /// this package list all images of device
//   ///
//   final Medium image;

//   ///
//   /// where selected is true, apply a check in the image
//   ///
//   final bool selected;

//   ///
//   ///this widget is usage how itemBuilder of painel: _ImagesPage
//   ///
//   const _ImageItem({required this.image, required this.selected});

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       child: Stack(
//         children: [
//           Hero(
//             tag: image.id,
//             child: Container(
//               decoration: BoxDecoration(
//                 image: DecorationImage(
//                   fit: BoxFit.cover,
//                   filterQuality: FilterQuality.high,
//                   image: ThumbnailProvider(
//                     mediumId: image.id,
//                     highQuality: true,
//                     height: 150,
//                     width: 150,
//                     mediumType: MediumType.image,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           if (selected)
//             Container(
//               color: Colors.grey.withOpacity(.3),
//               child: Center(
//                 child: Stack(
//                   children: [
//                     const Icon(
//                       Icons.done,
//                       size: 52,
//                       color: Colors.white,
//                     ),
//                     Icon(
//                       Icons.done,
//                       size: 50,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           Align(
//             alignment: Alignment.topRight,
//             child: IconButton(
//               color: Colors.white,
//               icon: const Icon(Icons.zoom_out_map_outlined),
//               onPressed: () async {
//                 image.getFile().then((value) {
//                   Navigator.of(context).push(MaterialPageRoute(
//                     builder: (context) {
//                       return Hero(
//                         tag: image.id,
//                         child: ViewImage(image: value.path),
//                       );
//                     },
//                   ));
//                 });
//               },
//             ),
//           )
//         ],
//       ),
//     );
//   }
// }
