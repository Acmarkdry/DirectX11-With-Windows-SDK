//***************************************************************************************
// Modified by X_Jun(MKXJun)
// Licensed under the MIT License.
//
//***************************************************************************************
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
// Developed by Minigraph
//
// Author:  James Stanard 
// Modified by X_Jun(MKXJun)
// Source at https://github.com/microsoft/DirectX-Graphics-Samples/tree/master/MiniEngine/Core/Shaders
// ������FXAA 3.11(PC Quality)�ļ�����ɫ���Ż�ʵ�֡�ʹ�ù�������(RWStructuredBuffer��ԭ�Ӽ���)
// ���������ܣ������������ƣ�
//   1) ��ˮƽ����ֱ��Ե�����ֿ��ɵ�����dispatches��������ɫ�����ӶȺͲ�����ķ�֧
//   2) �ӳ�д����������ɫֱ�������buffer������ϣ��Ӷ������ɢ��ȡ��д���Σ��
//   3) ��ַ�޸�ԭbuffer������ʹ��ping-pong buffers�����ٴ�����ڴ����Ҫ
//     ���������ᵽ��ʹ��UAVs�����ĺô�����һ��pass������groupshared�ڴ����洢lumaֵ��
// ��һ�����ٻ�ȡ�ʹ���
// 
// ��һ���Ż��������ظ�֪����(luma)�����ɡ�֮ǰ��ʵ��ʹ��sRGB��Ϊlog-luminance�����ý��ơ�
// ����׼ȷ��log-luminance��ʾ�����㷨�Ը��ߵ���ִֵ�У�ͬʱ��Ȼ�������������ȷ�Χ���ҵ�����
// ��֪�ı�Ե������ʹ��(1 - 2^(-4L)) * 16/15�Ľ��Ʒ�ʽ������
//     L=dot( LinearRGB, float3(0.212671, 0.715160, 0.072169) ).
// �����ַ�ʽ�£��Ƽ�ʹ��0.2����ֵ����log-luminance
//

// Original Boilerplate:
//
/*============================================================================


                    NVIDIA FXAA 3.11 by TIMOTHY LOTTES


------------------------------------------------------------------------------
COPYRIGHT (C) 2010, 2011 NVIDIA CORPORATION. ALL RIGHTS RESERVED.
------------------------------------------------------------------------------
TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THIS SOFTWARE IS PROVIDED
*AS IS* AND NVIDIA AND ITS SUPPLIERS DISCLAIM ALL WARRANTIES, EITHER EXPRESS
OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL NVIDIA
OR ITS SUPPLIERS BE LIABLE FOR ANY SPECIAL, INCIDENTAL, INDIRECT, OR
CONSEQUENTIAL DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR
LOSS OF BUSINESS PROFITS, BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION,
OR ANY OTHER PECUNIARY LOSS) ARISING OUT OF THE USE OF OR INABILITY TO USE
THIS SOFTWARE, EVEN IF NVIDIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGES.
*/

#ifndef FXAA_CS_HLSL
#define FXAA_CS_HLSL



#ifndef USE_LUMA_INPUT_BUFFER
#define USE_LUMA_INPUT_BUFFER 1
#endif

#ifndef SUPPORT_TYPED_UAV_LOADS
#define SUPPORT_TYPED_UAV_LOADS 0
#endif

#ifndef DO_VERTICAL_ORIENTATION
#define DO_VERTICAL_ORIENTATION 0
#endif

cbuffer CB : register(b0)
{
    float2 g_TexelSize;
    float  g_QualityEdgeThreshold; // default = 0.2, lower is more expensive
    float  g_QualityEdgeThresholdMin;
    float  g_QualitySubPix; // default = 0.75, lower blurs less
    uint   g_LastQueueIndex;
    uint2  g_StartPixel;
}


RWByteAddressBuffer g_WorkCountRW : register(u0);
RWByteAddressBuffer g_WorkQueueRW : register(u1);
RWBuffer<float3> g_ColorQueueRW : register(u2);

ByteAddressBuffer g_WorkCount : register(t1);
ByteAddressBuffer g_WorkQueue : register(t2);
Buffer<float3> g_ColorQueue : register(t3);


#if SUPPORT_TYPED_UAV_LOADS == 1
RWTexture2D<float4> g_ColorOutput : register(u3); // Pass2ʹ��
Texture2D<float4> g_TextureInput : register(t0); // R8G8B8A8_UNORM
float3 FetchColor(int2 st) { return g_Color[st].rgb; }
#else
RWTexture2D<uint> g_ColorOutput : register(u3);
Texture2D<uint> g_TextureInput : register(t0);

uint PackColor(float4 color, int2 st)
{
    uint R = uint(color.r * 255);
    uint G = uint(color.g * 255) << 8;
    uint B = uint(color.b * 255) << 16;
    uint A = uint(color.a * 255) << 24;
    uint packedColor = R | G | B | A;
    return packedColor;
}

float3 FetchColor(int2 st) 
{
    uint packedColor = g_TextureInput[st];
    return float3((packedColor & 0xFF),
                  ((packedColor >> 8) & 0xFF),
                  ((packedColor >> 16) & 0xFF)) / 255.0f;
}
#endif

// ���ʹ��Ԥ�����luma������Ϊ�����ȡ�����������pass2ʹ��
#if USE_LUMA_INPUT_BUFFER == 1
Texture2D<float> g_Luma : register(t1);
#else
RWTexture2D<float> g_LumaRW : register(u3);
#endif

SamplerState g_SamplerLinearClamp : register(s0);

#define BOUNDARY_SIZE 1
#define GROUP_WIDTH 8
#define ROW_WIDTH (8 + BOUNDARY_SIZE * 2)
groupshared float gs_LumaCache[ROW_WIDTH * ROW_WIDTH]; // ������Pass1




float RGBToLogLuminance(float3 LinearRGB)
{
    float Luma = dot(LinearRGB, float3(0.212671, 0.715160, 0.072169));
    return log2(1 + Luma * 15) / 4;
}

[numthreads(GROUP_WIDTH, GROUP_WIDTH, 1)]
void FXAAPass1CS(uint3 Gid : SV_GroupID, 
                 uint GI : SV_GroupIndex, 
                 uint3 GTid : SV_GroupThreadID, 
                 uint3 DTid : SV_DispatchThreadID)
{
    uint2 PixelCoord = DTid.xy + g_StartPixel;

#if USE_LUMA_INPUT_BUFFER == 1
    // ÿ���̶߳�ȡ4��lumas��LDS(Local Data Storage)����ֻ����Ҫ����䵽���ػ�����
    if (max(GTid.x, GTid.y) < ROW_WIDTH / 2)
    {
        int2 ThreadUL = PixelCoord + GTid.xy - (BOUNDARY_SIZE - 1);
        // w z
        // x y
        float4 Luma4 = g_Luma.Gather(g_SamplerLinearClamp, ThreadUL * g_TexelSize);
        uint LoadIndex = (GTid.x + GTid.y * ROW_WIDTH) * 2;
        gs_LumaCache[LoadIndex                ] = Luma4.w;
        gs_LumaCache[LoadIndex + 1            ] = Luma4.z;
        gs_LumaCache[LoadIndex + ROW_WIDTH    ] = Luma4.x;
        gs_LumaCache[LoadIndex + ROW_WIDTH + 1] = Luma4.y;
    }
#else
    // ���ڴ�ʱ�����ò���Gather()���ҿ��ǵ��߽��������⣬
    // ������ÿ���̶߳�ȡ��������(��ֻ��һ�����̻߳��ȡ).
    if (GI < ROW_WIDTH * ROW_WIDTH / 2)
    {
        uint LdsCoord = GI;
        int2 UavCoord = g_StartPixel + uint2(GI % ROW_WIDTH, GI / ROW_WIDTH) + Gid.xy * GROUP_WIDTH - BOUNDARY_SIZE;
        float Luma1 = RGBToLogLuminance(FetchColor(UavCoord));
        g_LumaRW[UavCoord] = Luma1;
        gs_LumaCache[LdsCoord] = Luma1;

        LdsCoord += ROW_WIDTH * ROW_WIDTH / 2;
        UavCoord += int2(0, ROW_WIDTH / 2);
        float Luma2 = RGBToLogLuminance(FetchColor(UavCoord));
        g_LumaRW[UavCoord] = Luma2;
        gs_LumaCache[LdsCoord] = Luma2;
    }
#endif

    GroupMemoryBarrierWithGroupSync();

    uint CenterIdx = (GTid.x + BOUNDARY_SIZE) + (GTid.y + BOUNDARY_SIZE) * ROW_WIDTH;

    //   N
    // W M E
    //   S
    float lumaN = gs_LumaCache[CenterIdx - ROW_WIDTH];
    float lumaW = gs_LumaCache[CenterIdx - 1];
    float lumaM = gs_LumaCache[CenterIdx];
    float lumaE = gs_LumaCache[CenterIdx + 1];
    float lumaS = gs_LumaCache[CenterIdx + ROW_WIDTH];

    //
    // ����Աȶȣ�ȷ���Ƿ�Ӧ�ÿ����
    //
    
    // ���5�������е����/��С������ȣ��õ��Աȶ�
    float lumaRangeMax = max(max(lumaN, lumaW), max(lumaE, max(lumaS, lumaM)));
    float lumaRangeMin = min(min(lumaN, lumaW), min(lumaE, min(lumaS, lumaM)));
    float lumaRange = lumaRangeMax - lumaRangeMin;
    
    // ������ȱ仯����һ����������ȳ�����ص���ֵ�����ߵ���һ��������ֵ��˵�����Ǵ��ڱ�Ե���򣬲������κο���ݲ���
    if (lumaRange < max(g_QualityEdgeThresholdMin, lumaRangeMax * g_QualityEdgeThreshold))
        return;

    // ��ȡ���ڽǵ�����
    float lumaNW = gs_LumaCache[CenterIdx - ROW_WIDTH - 1];
    float lumaNE = gs_LumaCache[CenterIdx - ROW_WIDTH + 1];
    float lumaSW = gs_LumaCache[CenterIdx + ROW_WIDTH - 1];
    float lumaSE = gs_LumaCache[CenterIdx + ROW_WIDTH + 1];

    float lumaNS = lumaN + lumaS;
    float lumaWE = lumaW + lumaE;
    float lumaNWSW = lumaNW + lumaSW;
    float lumaNESE = lumaNE + lumaSE;
    float lumaSWSE = lumaSW + lumaSE;
    float lumaNWNE = lumaNW + lumaNE;

    // ����ˮƽ�ʹ�ֱ�Աȶȣ������ж��� �ֲ�ˮƽ�߽� ���� �ֲ���ֱ�߽�
    float edgeHorz = abs(lumaNWSW - 2.0 * lumaW) + abs(lumaNS - 2.0 * lumaM) * 2.0 + abs(lumaNESE - 2.0 * lumaE);
    float edgeVert = abs(lumaSWSE - 2.0 * lumaS) + abs(lumaWE - 2.0 * lumaM) * 2.0 + abs(lumaNWNE - 2.0 * lumaN);

    // Ҳ����3x3����ľֲ��Աȶȣ�����ʶ��������
    float avgNeighborLuma = ((lumaNS + lumaWE) * 2.0 + lumaNWSW + lumaNESE) / 12.0;
    float subpixelShift = saturate(pow(smoothstep(0, 1, abs(avgNeighborLuma - lumaM) / lumaRange), 2) * g_QualitySubPix * 2);

    // �ҳ��ݶ��ݶ�
    float NegGrad = (edgeHorz >= edgeVert ? lumaN : lumaW) - lumaM;
    float PosGrad = (edgeHorz >= edgeVert ? lumaS : lumaE) - lumaM;
    uint GradientDir = abs(PosGrad) >= abs(NegGrad) ? 1 : 0;
    // ѹ�������ضԱȶ�
    uint Subpix = uint(subpixelShift * 254.0) & 0xFE;

    // �������ͷ: [ 12 bits Y | 12 bits X | 7 bit ������ | 1 bit �ݶȷ��� ]
    uint WorkHeader = DTid.y << 20 | DTid.x << 8 | Subpix | GradientDir;

    // ˮƽ�߽�Ĵ�ͷ����䣬��ֱ�߽�Ĵ�β�����
    // [h0, h1, ..., hm, /, ..., / , vn, ... v1, v0]
    if (edgeHorz >= edgeVert)
    {
        uint WorkIdx;
        g_WorkCountRW.InterlockedAdd(0, 1, WorkIdx);
        g_WorkQueueRW.Store(WorkIdx * 4, WorkHeader);
        g_ColorQueueRW[WorkIdx] = FetchColor(PixelCoord + uint2(0, 2 * GradientDir - 1));
    }
    else
    {
        uint WorkIdx;
        g_WorkCountRW.InterlockedAdd(4, 1, WorkIdx);
        // ���Ŵ�
        WorkIdx = g_LastQueueIndex - WorkIdx;
        g_WorkQueueRW.Store(WorkIdx * 4, WorkHeader);
        g_ColorQueueRW[WorkIdx] = FetchColor(PixelCoord + uint2(2 * GradientDir - 1, 0));
    }
}

/*==========================================================================*/

#if USE_LUMA_INPUT_BUFFER == 1
[numthreads(64, 1, 1)]
void main(uint3 Gid : SV_GroupID, 
          uint GI : SV_GroupIndex, 
          uint3 GTid : SV_GroupThreadID, 
          uint3 DTid : SV_DispatchThreadID)
{
#if DO_VERTICAL_ORIENTATION == 1
    uint ItemIdx = LastQueueIndex - DTid.x;
#else
    uint ItemIdx = DTid.x;
#endif
    uint WorkHeader = g_WorkQueue.Load(ItemIdx * 4);
    uint2 ST = g_StartPixel + (uint2(WorkHeader >> 8, WorkHeader >> 20) & 0xFFF);
    uint GradientDir = WorkHeader & 1; // Determines which side of the pixel has the highest contrast
    float Subpix = (WorkHeader & 0xFE) / 254.0 * 0.5; // 7-bits to encode [0, 0.5]

#if DO_VERTICAL_ORIENTATION == 1
    float NextLuma = g_Luma[ST + int2(GradientDir * 2 - 1, 0)];
    float2 StartUV = (ST + float2(GradientDir, 0.5)) * g_TexelSize;
#else
    float NextLuma = g_Luma[ST + int2(0, GradientDir * 2 - 1)];
    float2 StartUV = (ST + float2(0.5, GradientDir)) * g_TexelSize;
#endif
    float ThisLuma = g_Luma[ST];
    float CenterLuma = (NextLuma + ThisLuma) * 0.5; // Halfway between this and next; center of the contrasting edge
    float GradientSgn = sign(NextLuma - ThisLuma); // Going down in brightness or up?
    float GradientMag = abs(NextLuma - ThisLuma) * 0.25; // How much contrast?  When can we stop looking?

    float NegDist = s_SampleDistances[NUM_SAMPLES];
    float PosDist = s_SampleDistances[NUM_SAMPLES];
    bool NegGood = false;
    bool PosGood = false;

    for (uint iter = 0; iter < NUM_SAMPLES; ++iter)
    {
        const float Distance = s_SampleDistances[iter];

#if DO_VERTICAL_ORIENTATION == 1
        float2 NegUV = StartUV - float2(0, g_TexelSize.y) * Distance;
        float2 PosUV = StartUV + float2(0, g_TexelSize.y) * Distance;
#else
        float2 NegUV = StartUV - float2(g_TexelSize.x, 0) * Distance;
        float2 PosUV = StartUV + float2(g_TexelSize.x, 0) * Distance;
#endif

        // Check for a negative endpoint
        float NegGrad = g_Luma.SampleLevel(g_SamplerLinearClamp, NegUV, 0) - CenterLuma;
        if (abs(NegGrad) >= GradientMag && Distance < NegDist)
        {
            NegDist = Distance;
            NegGood = sign(NegGrad) == GradientSgn;
        }

        // Check for a positive endpoint
        float PosGrad = Luma.SampleLevel(g_SamplerLinearClamp, PosUV, 0) - CenterLuma;
        if (abs(PosGrad) >= GradientMag && Distance < PosDist)
        {
            PosDist = Distance;
            PosGood = sign(PosGrad) == GradientSgn;
        }
    }

    // Ranges from 0.0 to 0.5
    float PixelShift = 0.5 - min(NegDist, PosDist) / (PosDist + NegDist);
    bool GoodSpan = NegDist < PosDist ? NegGood : PosGood;
    PixelShift = max(Subpix, GoodSpan ? PixelShift : 0.0);

    if (PixelShift > 0.01)
    {
#ifdef DEBUG_OUTPUT
#if SUPPORT_TYPED_UAV_LOADS == 1
        g_ColorOutput[ST] = float3(2.0 * PixelShift, 1.0 - 2.0 * PixelShift, 0);
#else
        g_ColorOutput[ST] = Pack_R11G11B10_FLOAT(float3(2.0 * PixelShift, 1.0 - 2.0 * PixelShift, 0));
#endif
#else
#if SUPPORT_TYPED_UAV_LOADS == 1
        g_ColorOutput[ST] = lerp(g_ColorOutput[ST], ColorQueue[ItemIdx], PixelShift);
#else
        g_ColorOutput[ST] = Pack_R11G11B10_FLOAT(lerp(Unpack_R11G11B10_FLOAT(g_ColorOutput[ST]), ColorQueue[ItemIdx], PixelShift));
#endif
#endif
    }
#ifdef DEBUG_OUTPUT
    else
    {
#if SUPPORT_TYPED_UAV_LOADS == 1
        g_ColorOutput[ST] = float3(0, 0, 0.25);
#else
        g_ColorOutput[ST] = Pack_R11G11B10_FLOAT(float3(0, 0, 0.25));
#endif
    }
#endif
}

#endif

#endif
