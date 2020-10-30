Shader "Custom/testWater"
{
    Properties
    {
        _Color("Color", Color) = (0,0,0,0.4)
        _VoronviSpeed("VoronviSpeed", Range(-10,10)) = 1.23
        _RippleSpeed("RippleSpeed", Vector) = (0.0, -0.2, .0, .0)
        _RippleAmount("RippleAmount", Range(1,10)) = 1
        _RippleContrast("RippleContrast", Range(0,1)) = 0.3
        _FadeAmount("FadeAmount", Range(0,10)) = 1
        _DisplacementAmount("DisplacementAmount", Range(-1,1)) = -0.25
    }
    SubShader
    {
        Tags {"Queue" = "Transparent" "RenderType" = "Transparent"}
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha
        //Cull front
        LOD 100

        Pass
        {
            CGPROGRAM
            
            // use "vert" function as the vertex shader
            #pragma vertex vert
            // use "frag" function as the pixel (fragment) shader
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            #include "UnityCG.cginc"


            fixed4 _Color;
            float _VoronviSpeed;
            float2 _RippleSpeed;
            int _RippleAmount; 
            int _FadeAmount;
            float _RippleContrast;
            float _DisplacementAmount;
         
            struct appdata
            {
                float4 vertex : POSITION;   // vertex position
                float2 uv : TEXCOORD0;      // texture coordinate
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;  // texture coordinate
                float4 vertex : SV_POSITION;    // clip space position
            };

            // Code from https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Voronoi-Node.html
            // And tweaked around with for this project

            inline float2 unity_voronoi_noise_randomVector(float2 UV, float offset)
            {
                float2x2 m = float2x2(15.27, 47.63, 99.41, 89.98);
                UV = frac(sin(mul(UV, m)) * 46839.32);
                return float2(sin(UV.y * +offset) * 0.5 + 0.5, cos(UV.x * offset) * 0.5 + 0.5);
            }

            void Unity_Voronoi_float(float2 UV, float AngleOffset, float CellDensity, out float Out, out float Cells)
            {
                float2 g = floor(UV * CellDensity);
                float2 f = frac(UV * CellDensity);
                float t = 8.0;
                float3 res = float3(8.0, 0.0, 0.0);

                for (int y = -1; y <= 1; y++)
                {
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 lattice = float2(x, y);
                        float2 offset = unity_voronoi_noise_randomVector(lattice + g, AngleOffset);
                        float d = distance(lattice + offset, f);
                        if (d < res.x)
                        {
                            res = float3(d, offset.x, offset.y);
                            Out = res.x;
                            Cells = res.y;
                        }
                    }
                }
            }

            void Unity_Remap_float(float In, float2 InMinMax, float2 OutMinMax, out float Out)  {
                Out = OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
            }

            inline float unity_noise_randomValue(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
            }

            inline float unity_noise_interpolate(float a, float b, float t)
            {
                return (1.0 - t) * a + (t * b);
            }

            inline float unity_valueNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                f = f * f * (3.0 - 2.0 * f);

                uv = abs(frac(uv) - 0.5);
                float2 c0 = i + float2(0.0, 0.0);
                float2 c1 = i + float2(1.0, 0.0);
                float2 c2 = i + float2(0.0, 1.0);
                float2 c3 = i + float2(1.0, 1.0);
                float r0 = unity_noise_randomValue(c0);
                float r1 = unity_noise_randomValue(c1);
                float r2 = unity_noise_randomValue(c2);
                float r3 = unity_noise_randomValue(c3);

                float bottomOfGrid = unity_noise_interpolate(r0, r1, f.x);
                float topOfGrid = unity_noise_interpolate(r2, r3, f.x);
                float t = unity_noise_interpolate(bottomOfGrid, topOfGrid, f.y);
                return t;
            }

            void Unity_SimpleNoise_float(float2 UV, float Scale, out float Out)
            {
                float t = 0.0;

                float freq = pow(2.0, float(0));
                float amp = pow(0.5, float(3 - 0));
                t += unity_valueNoise(float2(UV.x * Scale / freq, UV.y * Scale / freq)) * amp;

                freq = pow(2.0, float(1));
                amp = pow(0.5, float(3 - 1));
                t += unity_valueNoise(float2(UV.x * Scale / freq, UV.y * Scale / freq)) * amp;

                freq = pow(2.0, float(2));
                amp = pow(0.5, float(3 - 2));
                t += unity_valueNoise(float2(UV.x * Scale / freq, UV.y * Scale / freq)) * amp;

                Out = t;
            }

            v2f vert (appdata v)  {
                v2f o;
            
                float noise;
                float remappedNoise;
                float cells;
                float ripple = mul(_Time, _RippleSpeed);
                float _temp = ripple + v.uv;
                float angleOffset = _VoronviSpeed * _Time * 5;
                float bottomFoam;
                float simpleNoise;

                Unity_Voronoi_float(v.uv.xy + ripple, angleOffset, 5, noise, cells);
                noise = pow(noise, _RippleAmount);

                // Remap lower values to the value of "_RippleContrast", standard 0.3 --> This takes away dark spots in the water
                Unity_Remap_float(noise, float2(0.0, 1.0), float2(_RippleContrast, 1.0), remappedNoise);
                bottomFoam = v.uv.x;
                bottomFoam = pow(bottomFoam, _FadeAmount);
                Unity_SimpleNoise_float(v.uv, 20, simpleNoise);
                bottomFoam = bottomFoam * simpleNoise;
                Unity_Remap_float(bottomFoam, float2(0.0, 1.0), float2(0.0, 5.0), bottomFoam);


                // Apply noise to the object-space position (v.vertex)
                v.vertex = v.vertex + _DisplacementAmount * (remappedNoise + bottomFoam);


                // transform position to clip space
                // (multiply with model*view*projection matrix)
                o.vertex = UnityObjectToClipPos(v.vertex);

                
               // o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);

                o.uv = v.uv;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float noise;
                float remappedNoise;
                float cells;
                float ripple = mul(_Time, _RippleSpeed);
                float _temp = ripple + i.uv;
                float angleOffset = _VoronviSpeed * _Time*5;
                float bottomFoam;
                float simpleNoise;

                Unity_Voronoi_float(i.uv.xy + ripple, angleOffset, 5, noise, cells);
                // _RippleAmount is how "dark" the ripples should be. Making them more visible. 
                noise = pow(noise, _RippleAmount);

                // Remap lower values to the value of "_RippleContrast", standard 0.3 --> This takes away dark spots in the water
                Unity_Remap_float(noise, float2(0.0, 1.0), float2(_RippleContrast, 1.0), remappedNoise);


                bottomFoam = i.uv.x;
                bottomFoam = pow(bottomFoam, _FadeAmount);
                Unity_SimpleNoise_float(i.uv, 20, simpleNoise);
                bottomFoam = bottomFoam * simpleNoise;
                Unity_Remap_float(bottomFoam, float2(0.0, 1.0), float2(0.0, 5.0), bottomFoam);

                
               
                return (remappedNoise + bottomFoam) * _Color;
               
            }

            ENDCG
        }
    }


}

