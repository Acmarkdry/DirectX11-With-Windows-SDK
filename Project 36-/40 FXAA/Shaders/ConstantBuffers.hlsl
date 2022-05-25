
#ifndef CONSTANT_BUFFERS_HLSL
#define CONSTANT_BUFFERS_HLSL

cbuffer CBChangesEveryInstanceDrawing : register(b0)
{
    matrix g_World;
    matrix g_WorldInvTranspose;
    matrix g_WorldView;
    matrix g_WorldViewProj;
}

cbuffer CBCascadedShadow : register(b1)
{
    matrix g_ShadowView;            
    float4 g_CascadeOffset[8];          // ShadowPT�����ƽ����
    float4 g_CascadeScale[8];           // ShadowPT�����������
    
    // ��Map-based Selection�������⽫������Ч��Χ�ڵ����ء�
    // ��û�б߽�ʱ��Min��Max�ֱ�Ϊ0��1
    float  g_MinBorderPadding;          // (kernelSize / 2) / (float)shadowSize
    float  g_MaxBorderPadding;          // 1.0f - (kernelSize / 2) / (float)shadowSize
    float  g_MagicPower;                // ����©�����õ�ָ��
    int    g_VisualizeCascades;         // 1ʹ�ò�ͬ����ɫ���ӻ�������Ӱ��0���Ƴ���
    
    float  g_CascadeBlendArea;          // ����֮���ص���ʱ�Ļ������
    float  g_TexelSize;                 // Shadow map�����ش�С
    int    g_PCFBlurForLoopStart;       // ѭ����ʼֵ��5x5��PCF�˴�-2��ʼ
    int    g_PCFBlurForLoopEnd;         // ѭ������ֵ��5x5��PCF��Ӧ����Ϊ3
    
    float  g_PCFDepthBias;              // ��Ӱƫ��ֵ
    float3 g_LightDir;                  // ��Դ����
    
    float  g_LightBleedingReduction;    // VSM©�������
    float  g_EvsmPosExp;                // EVSM����ָ����
    float  g_EvsmNegExp;                // EVSM�ĸ�ָ����
    int    g_16BitShadow;               // �Ƿ�16λ��Ӱ��ʽ
    
    float4 g_CascadeFrustumsEyeSpaceDepthsData[2]; // ��ͬ����׶��Զƽ���Zֵ���������ֿ�
    // ���ϸ���˵�ǲ�����cbuffer�ڵģ���Ӧ�����ⲿȥ����
    static float g_CascadeFrustumsEyeSpaceDepths[8] = (float[8]) g_CascadeFrustumsEyeSpaceDepthsData;
}


#endif // CONSTANTBUFFERS_HLSL
