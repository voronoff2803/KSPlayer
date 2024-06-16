//
//  MetalRender.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/11.
//
import Accelerate
import CoreVideo
import FFmpegKit
import Foundation
import Metal
import QuartzCore
import simd

public class MetalRender {
    public static let device = MTLCreateSystemDefaultDevice()!
    public static var mtlTextureCache: CVMetalTextureCache? = {
        var mtlTextureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                  nil,
                                  device,
                                  nil,
                                  &mtlTextureCache)
        return mtlTextureCache
    }()

    private let library: MTLLibrary = {
        var library: MTLLibrary!
        library = device.makeDefaultLibrary()
        if library == nil {
            library = try? device.makeDefaultLibrary(bundle: .module)
        }
        return library
    }()

    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private let commandQueue = MetalRender.device.makeCommandQueue()
    private lazy var samplerState: MTLSamplerState? = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        return MetalRender.device.makeSamplerState(descriptor: samplerDescriptor)
    }()

    private lazy var colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.videoRange.buffer

    private lazy var colorConversion601FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.buffer

    private lazy var colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.videoRange.buffer

    private lazy var colorConversion709FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.buffer

    private lazy var colorConversionSMPTE240MVideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.videoRange.buffer

    private lazy var colorConversionSMPTE240MFullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.buffer

    private lazy var colorConversion2020VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.videoRange.buffer

    private lazy var colorConversion2020FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.buffer

    private lazy var colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = SIMD3<Float>(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0).buffer

    private lazy var colorOffsetFullRangeMatrixBuffer: MTLBuffer? = SIMD3<Float>(0, -128.0 / 255.0, -128.0 / 255.0).buffer

    private lazy var leftShiftMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(1, 1, 1)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    private lazy var leftShiftSixMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(64, 64, 64)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    private lazy var yuv = makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: false)
    private lazy var yuvp010LE = makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: false, bitDepth: 10)
    private lazy var nv12 = makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: false)
    private lazy var p010LE = makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: false, bitDepth: 10)
    private lazy var bgra = makePipelineState(fragmentFunction: "displayTexture", isSphere: false)

    private lazy var yuvSphere = makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true)
    private lazy var yuvp010LESphere = makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true, bitDepth: 10)
    private lazy var nv12Sphere = makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true)
    private lazy var p010LESphere = makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true, bitDepth: 10)
    private lazy var bgraSphere = makePipelineState(fragmentFunction: "displayTexture", isSphere: true)
    private lazy var iCtCp10LE = makePipelineState(fragmentFunction: "displayICtCpTexture", bitDepth: 10)
    private lazy var iCtCpBiPlanar10LE = makePipelineState(fragmentFunction: "displayICtCpBiPlanarTexture", bitDepth: 10)
    private var pipelineMap = [String: MTLRenderPipelineState]()
    func clear(drawable: MTLDrawable) {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    @MainActor
    func draw(pixelBuffer: PixelBufferProtocol, display: DisplayEnum, drawable: CAMetalDrawable, doviData: dovi_metadata?) {
        let inputTextures = pixelBuffer.textures()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard !inputTextures.isEmpty, let commandBuffer = commandQueue?.makeCommandBuffer(), let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        let state = pipeline(pixelBuffer: pixelBuffer, doviData: doviData, isSphere: display.isSphere)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        setFragmentBuffer(pixelBuffer: pixelBuffer, encoder: encoder, doviData: doviData)
        display.set(encoder: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func setFragmentBuffer(pixelBuffer: PixelBufferProtocol, encoder: MTLRenderCommandEncoder, doviData: dovi_metadata?) {
        if pixelBuffer.planeCount > 1 {
            let isFullRangeVideo = pixelBuffer.isFullRangeVideo
            let leftShift = pixelBuffer.leftShift == 0 ? leftShiftMatrixBuffer : leftShiftSixMatrixBuffer
            if var doviData {
                doviData.linear = KSOptions.doviMatrix * doviData.linear
                let buffer1 = MetalRender.device.makeBuffer(bytes: &doviData, length: MemoryLayout<dovi_metadata>.size)
                buffer1?.label = "dovi"
                encoder.setFragmentBuffer(buffer1, offset: 0, index: 0)
                encoder.setFragmentBuffer(leftShift, offset: 0, index: 1)
            } else {
                let buffer1: MTLBuffer?
                let yCbCrMatrix = pixelBuffer.yCbCrMatrix
                if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 {
                    buffer1 = isFullRangeVideo ? colorConversion709FullRangeMatrixBuffer : colorConversion709VideoRangeMatrixBuffer
                } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 {
                    buffer1 = isFullRangeVideo ? colorConversionSMPTE240MFullRangeMatrixBuffer : colorConversionSMPTE240MVideoRangeMatrixBuffer
                } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 {
                    buffer1 = isFullRangeVideo ? colorConversion2020FullRangeMatrixBuffer : colorConversion2020VideoRangeMatrixBuffer
                } else {
                    buffer1 = isFullRangeVideo ? colorConversion601FullRangeMatrixBuffer : colorConversion601VideoRangeMatrixBuffer
                }
                let buffer2 = isFullRangeVideo ? colorOffsetFullRangeMatrixBuffer : colorOffsetVideoRangeMatrixBuffer
                encoder.setFragmentBuffer(buffer1, offset: 0, index: 0)
                encoder.setFragmentBuffer(buffer2, offset: 0, index: 1)
                encoder.setFragmentBuffer(leftShift, offset: 0, index: 2)
            }
        }
    }

    private func pipeline(pixelBuffer: PixelBufferProtocol, doviData: dovi_metadata?, isSphere: Bool) -> MTLRenderPipelineState {
        let planeCount = pixelBuffer.planeCount
        let bitDepth = pixelBuffer.bitDepth
        switch planeCount {
        case 3:
            if bitDepth == 10 {
                if let doviData {
                    if let source = doviData.pipeline {
                        return pipeline(source: source, fragmentFunction: "displayICtCpTexture")
                    } else {
                        return iCtCp10LE
                    }
                } else {
                    return isSphere ? yuvp010LESphere : yuvp010LE
                }
            } else {
                return isSphere ? yuvSphere : yuv
            }
        case 2:
            if bitDepth == 10 {
                if let doviData {
                    if let source = doviData.pipeline {
                        return pipeline(source: source, fragmentFunction: "displayICtCpBiPlanarTexture")
                    } else {
                        return iCtCpBiPlanar10LE
                    }
                } else {
                    return isSphere ? p010LESphere : p010LE
                }
            } else {
                return isSphere ? nv12Sphere : nv12
            }
        default:
            return isSphere ? bgraSphere : bgra
        }
    }

    private func makePipelineState(fragmentFunction: String, isSphere: Bool = false, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        library.makePipelineState(vertexFunction: isSphere ? "mapSphereTexture" : "mapTexture", fragmentFunction: fragmentFunction, bitDepth: bitDepth)
    }

    private func pipeline(source: String, fragmentFunction: String, bitDepth: Int32 = 10) -> MTLRenderPipelineState {
        if let pipeline = pipelineMap[source] {
            return pipeline
        }
        var library = try! MetalRender.device.makeLibrary(source: source, options: nil)
        let pipeline = library.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: fragmentFunction, bitDepth: 10)
        pipelineMap[source] = pipeline
        return pipeline
    }

    static func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture] {
//        guard let iosurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
//            return []
//        }
//        let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
//        return (0 ..< formats.count).compactMap { index in
//            let width = pixelBuffer.widthOfPlane(at: index)
//            let height = pixelBuffer.heightOfPlane(at: index)
//            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[index], width: width, height: height, mipmapped: false)
//            return device.makeTexture(descriptor: descriptor, iosurface: iosurface, plane: index)
//        }
        // 苹果推荐用textureCache
        guard let mtlTextureCache else {
            return []
        }
        let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
        return (0 ..< formats.count).compactMap { index in
            let width = pixelBuffer.widthOfPlane(at: index)
            let height = pixelBuffer.heightOfPlane(at: index)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[index], width: width, height: height, mipmapped: false)
            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                      mtlTextureCache,
                                                      pixelBuffer,
                                                      nil,
                                                      formats[index],
                                                      width,
                                                      height,
                                                      index,
                                                      &cvTexture)
            if let cvTexture {
                return CVMetalTextureGetTexture(cvTexture)
            }
            return nil
        }
    }

    static func textures(formats: [MTLPixelFormat], widths: [Int], heights: [Int], buffers: [MTLBuffer?], lineSizes: [Int]) -> [MTLTexture] {
        (0 ..< formats.count).compactMap { i in
            guard let buffer = buffers[i] else {
                return nil
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[i], width: widths[i], height: heights[i], mipmapped: false)
            descriptor.storageMode = buffer.storageMode
            return buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: lineSizes[i])
        }
    }
}

// swiftlint:disable identifier_name
// private let kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 = vImage_YpCbCrToARGBMatrix(Kr: 0.299, Kb: 0.114)
// private let kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 = vImage_YpCbCrToARGBMatrix(Kr: 0.2126, Kb: 0.0722)
private let kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995 = vImage_YpCbCrToARGBMatrix(Kr: 0.212, Kb: 0.087)
private let kvImage_YpCbCrToARGBMatrix_ITU_R_2020 = vImage_YpCbCrToARGBMatrix(Kr: 0.2627, Kb: 0.0593)
extension vImage_YpCbCrToARGBMatrix {
    /**
     https://en.wikipedia.org/wiki/YCbCr
     @textblock
            | R |    | 1    0                                                            2-2Kr |   | Y' |
            | G | = | 1   -Kb * (2 - 2 * Kb) / Kg   -Kr * (2 - 2 * Kr) / Kg |  | Cb |
            | B |    | 1   2 - 2 * Kb                                                     0  |  | Cr |
     @/textblock
     */
    init(Kr: Float, Kb: Float) {
        let Kg = 1 - Kr - Kb
        self.init(Yp: 1, Cr_R: 2 - 2 * Kr, Cr_G: -Kr * (2 - 2 * Kr) / Kg, Cb_G: -Kb * (2 - 2 * Kb) / Kg, Cb_B: 2 - 2 * Kb)
    }

    var videoRange: vImage_YpCbCrToARGBMatrix {
        vImage_YpCbCrToARGBMatrix(Yp: 255 / 219 * Yp, Cr_R: 255 / 224 * Cr_R, Cr_G: 255 / 224 * Cr_G, Cb_G: 255 / 224 * Cb_G, Cb_B: 255 / 224 * Cb_B)
    }

    var simd: simd_float3x3 {
        // 初始化函数是用columns
        simd_float3x3([Yp, Yp, Yp], [0.0, Cb_G, Cb_B], [Cr_R, Cr_G, 0.0])
    }

    var buffer: MTLBuffer? {
        simd.buffer
    }
}

extension simd_float3x3 {
    var buffer: MTLBuffer? {
        var matrix = self
        let buffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }
}

extension simd_float3 {
    var buffer: MTLBuffer? {
        var matrix = self
        let buffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3>.size)
        buffer?.label = "colorOffset"
        return buffer
    }
}

// swiftlint:enable identifier_name

extension MTLLibrary {
    func makePipelineState(vertexFunction: String, fragmentFunction: String, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)
        descriptor.vertexFunction = makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = makeFunction(name: fragmentFunction)
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float4>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<simd_float2>.stride
        descriptor.vertexDescriptor = vertexDescriptor
        // swiftlint:disable force_try
        return try! device.makeRenderPipelineState(descriptor: descriptor)
        // swftlint:enable force_try
    }
}

extension dovi_metadata {
    var pipeline: String? {
        var str = """
        #include <metal_stdlib>
        using namespace metal;

        inline float3 pqEOTF(float3 rgb) {
        rgb = pow(max(rgb,0), float3(4096.0/(2523 * 128)));
        rgb = max(rgb - float3(3424./4096), 0.0) / (float3(2413./4096 * 32) - float3(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float3(4096.0 * 4 / 2610));
        return rgb;
        }

        inline float3 pqOETF(float3 rgb) {
        rgb = pow(max(rgb,0), float3(2610./4096 / 4));
        rgb = (float3(3424./4096) + float3(2413./4096 * 32) * rgb) / (float3(1.0) + float3(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float3(2523./4096 * 128));
        return rgb;
        }

        struct VertexIn
        {
        float4 pos [[attribute(0)]];
        float2 uv [[attribute(1)]];
        };

        struct VertexOut {
        float4 renderedCoordinate [[position]];
        float2 textureCoordinate;
        };

        vertex VertexOut mapTexture(VertexIn input [[stage_in]]) {
        VertexOut outVertex;
        outVertex.renderedCoordinate = input.pos;
        outVertex.textureCoordinate = input.uv;
        return outVertex;
        }

        struct dovi_metadata {
        // Colorspace transformation metadata
        float3x3 nonlinear;     // before PQ, also called "ycc_to_rgb"
        float3x3 linear;        // after PQ, also called "rgb_to_lms"
        simd_float3 nonlinear_offset;  // input offset ("ycc_to_rgb_offset")
        float minLuminance;
        float maxLuminance;
        struct reshape_data {
        float4 coeffs[8];
        float4 mmr[8*6];
        float pivots[7];
        float lo;
        float hi;
        uint8_t min_order;
        uint8_t max_order;
        uint8_t num_pivots;
        bool has_poly;
        bool has_mmr;
        bool mmr_single;
        } comp[3];
        };

        float reshape_poly(float s, float4 coeffs)
        {
        s = (coeffs.z * s + coeffs.y) * s + coeffs.x;
        return s;
        }

        #define pivot(i) float4(bool4(s >= data.pivots[i]))
        #define coef(i) data.coeffs[i]

        """
        str += """
        float3 reshape3(float3 rgb, constant dovi_metadata::reshape_data datas[3]) {
        float3 sig = clamp(rgb, 0.0, 1.0);
        float s;
        float4 coeffs;
        dovi_metadata::reshape_data data;

        """
        let array = Array(tuple: comp)
        for i in 0 ..< 3 {
            let data = array[i]
            str += """
            s = sig[\(i)];
            data = datas[\(i)];

            """
            if data.num_pivots > 2 {
                str += """
                coeffs = mix(mix(mix(coef(0), coef(1), pivot(0)),
                             mix(coef(2), coef(3), pivot(2)),
                             pivot(1)),
                         mix(mix(coef(4), coef(5), pivot(4)),
                             mix(coef(6), coef(7), pivot(6)),
                             pivot(5)),
                         pivot(3));

                """
            } else {
                str += """
                coeffs = data.coeffs[0];

                """
            }
            if data.has_poly, data.has_mmr {
                str += """
                if (coeffs.w == 0.0) {
                    s = reshape_poly(s, coeffs);
                } else {
                    \(data.reshapeMMR())
                }

                """
            } else if data.has_poly {
                str += """
                s = reshape_poly(s, coeffs);

                """
            } else {
                str += """
                {
                    \(data.reshapeMMR())
                }

                """
            }
            str += """
            rgb[\(i)] = clamp(s, data.lo, data.hi);

            """
        }
        str += """
        return rgb;
        }

        """
        str += """
            fragment float4 displayICtCpTexture(VertexOut in [[ stage_in ]],
                                    texture2d<half> yTexture [[ texture(0) ]],
                                    texture2d<half> uTexture [[ texture(1) ]],
                                    texture2d<half> vTexture [[ texture(2) ]],
                                    sampler textureSampler [[ sampler(0) ]],
                                    constant dovi_metadata& data [[ buffer(0) ]],
                                    constant uchar3& leftShift [[ buffer(1) ]])
        {
        float3 rgb;
        rgb.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb = reshape3(rgb, data.comp);
        rgb = rgb*float3(leftShift);
        rgb = data.nonlinear*(rgb + data.nonlinear_offset);
        rgb = pqEOTF(rgb);
        rgb = data.linear*rgb;
        rgb = pqOETF(rgb);
        return float4(rgb, 1);
        }

        fragment float4 displayICtCpBiPlanarTexture(VertexOut in [[ stage_in ]],
                                            texture2d<half> lumaTexture [[ texture(0) ]],
                                            texture2d<half> chromaTexture [[ texture(1) ]],
                                            sampler textureSampler [[ sampler(0) ]],
                                            constant dovi_metadata& data [[ buffer(0) ]],
                                            constant uchar3& leftShift [[ buffer(1) ]])
        {
        float3 rgb;
        rgb.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.yz = float2(chromaTexture.sample(textureSampler, in.textureCoordinate).rg);
        rgb = reshape3(rgb, data.comp);
        rgb = rgb*float3(leftShift);
        rgb = data.nonlinear*(rgb + data.nonlinear_offset);
        rgb = pqEOTF(rgb);
        rgb = data.linear*rgb;
        rgb = pqOETF(rgb);
        return float4(rgb, 1);
        }
        """
        return str
    }
}

extension reshape_data {
    func reshapeMMR() -> String {
        var str = """
        """
        if mmr_single {
            str += """
            uint mmr_idx = 0;
            """
        } else {
            str += """
            uint mmr_idx = coeffs.y;
            """
        }
        str += """
        s = coeffs.x;
        float4 sigX;
        s = coeffs.x;
        sigX.xyz = sig.xxy * sig.yzz;
        sigX.w = sigX.x * sig.z;
        s += dot(data.mmr[mmr_idx + 0].xyz, sig);
        s += dot(data.mmr[mmr_idx + 1], sigX);
        """
        if max_order >= 2 {
            if min_order < max_order {
                str += """
                uint order = uint(coeffs.w);
                """
            }
            if min_order < 2 {
                str += """
                if (order >= 2) {
                """
            }
            str += """
            float3 sig2 = sig * sig;
            float4 sigX2 = sigX * sigX;
            s += dot(data.mmr[mmr_idx + 2].xyz, sig2);
            s += dot(data.mmr[mmr_idx + 3], sigX2);
            """
            if max_order == 3 {
                if min_order < 3 {
                    str += """
                    if (order >= 3) {
                    """
                }
                str += """
                s += dot(data.mmr[mmr_idx + 4].xyz, sig2 * sig);
                s += dot(data.mmr[mmr_idx + 5], sigX2 * sigX);
                """
                if min_order < 3 {
                    str += """
                    }
                    """
                }
            }
            if min_order < 2 {
                str += """
                }
                """
            }
        }
        return str
    }
}
