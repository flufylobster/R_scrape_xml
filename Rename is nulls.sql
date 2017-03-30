 /* rename nulls */
 select  ri+ri2+',' from 
 
 (select distinct 
                     'isnull(_MC_v2_'+ riskcode+',1)' as ri, riskcode  
                    
                from intelreports..fp_riskindicators ) a 
left join (select distinct ' as _MC_v2_'+riskcode as ri2 ,riskcode from  intelreports..fp_riskindicators) b
on a.riskcode=b.riskcode





/*parameter coef*/
select distinct 'isnull(_MC_v2_'+riskcode+',0)'+' '+'*'+' '+'isnull(_MC_v2_'+riskcode+'0'+',0)'+' '+'+' from  intelreports..fp_riskindicators

/*pull coef*/
select ri+ri2+',' parameter from
(select distinct 'isnull(_MC_v2_'+riskcode+',0)'+' '+'*'+' '+'isnull(_MC_v2_'+riskcode+'0'+',0)'+' ' ri,riskcode from  intelreports..fp_riskindicators) a
left join (select distinct ' as _MC_v2_'+riskcode as ri2 ,riskcode from  intelreports..fp_riskindicators) b
on a.riskcode=b.riskcode




	select * from #noncore_pre_scoring where approvalid='24H47GD'		
	select * from analytics..orig_parameter_coef_v2		
	
	
	
	
	select 
				    intercept intercept,
					(case when _mc_add_flag=0 then _mc_add_flag0
						   else 0 end) as add_flag,
					(case when _mc_paymentfrequency='14 Day' then _mc_paymentfrequency14_day
						  when _mc_paymentfrequency='28 Day' then _mc_paymentfrequency28_day
						  when _mc_paymentfrequency='bi-weekly' then _mc_paymentfrequencybi_weekly
						  when _mc_paymentfrequency='Monthly' then 0 end) payfreq,
					(case when _mc_primarypaymentmethod='ACH' then _mc_primarypaymentmethodACH
						  else 0 end) primpay,
					(case when _mc_seasonality=1 then _mc_seasonality1
					      when _mc_seasonality=2 then _mc_seasonality2
						  when _mc_seasonality=3 then _mc_seasonality3
						  when _mc_seasonality=4 then _mc_seasonality4
						  when _mc_seasonality=5 then _mc_seasonality5
						  when _mc_seasonality=6 then _mc_seasonality6
						  when _mc_seasonality=7 then _mc_seasonality7
						  when _mc_seasonality=8 then _mc_seasonality8
						  when _mc_seasonality=9 then _mc_seasonality9
						  when _mc_seasonality=10 then _mc_seasonality10
						  when _mc_seasonality=11then _mc_seasonality11
						  else 0 end) season,
					(case when _MC_state_flag=0 then _MC_state_flag0
								else 0 end) state_flag,

						
					(case when _mc_zipgroup1='0' then _mc_zipgroup10
						  when _mc_zipgroup1='1' then _mc_zipgroup11
						  when _mc_zipgroup1='2' then _mc_zipgroup12
						  when _mc_zipgroup1='3' then _mc_zipgroup13
						  when _mc_zipgroup1='4' then _mc_zipgroup14
						  when _mc_zipgroup1='5' then _mc_zipgroup15
						  when _mc_zipgroup1='6' then _mc_zipgroup16
						  when _mc_zipgroup1='7' then _mc_zipgroup17
						  when _mc_zipgroup1='8' then _mc_zipgroup18
						  else 0 end )  zipgroup,
					(case when _mc_card_appear_number=0 then _mc_card_appear_number0
						  when _mc_card_appear_number=1 then _mc_card_appear_number1
						  when _mc_card_appear_number=2 then _mc_card_appear_number2
						  else 0 end) card_appear, 
					( case when _mc_sku_dif=0 then _mc_sku_dif0
						   when _mc_sku_dif=1 then _mc_sku_dif1
						   else 0 end) sku,
					( case when _mc_languagepreference=0 then _mc_languagepreference0
						   when _mc_languagepreference=1 then _mc_languagepreference1
						   when _mc_languagepreference=2 then _mc_languagepreference2
						   when _mc_languagepreference=3 then _mc_languagepreference3
						   else 0 end) lang_pref,
					( case when _mc_idtype='Drivers License' then _mc_idtypeDrivers_License
						   when _mc_idtype='Green Card' then _mc_idtypeGreen_Card
						   when _mc_idtype='Military ID' then _mc_idtypeMilitary_ID
						   when _mc_idtype='MMCC' then _mc_idtypeMMCC
						   when _mc_idtype='Missing' then _mc_idtypeMissing
						   when _mc_idtype='Passport' then _mc_idtypePassport
						   when _mc_idtype='State ID' then _mc_idtypeState_ID
							else 0 end ) idtype,
				    ( case when _mcfp_quintile=1 then _mcfp_quintile1
						   when _mcfp_quintile=2 then _mcfp_quintile2
						   when _mcfp_quintile=3 then _mcfp_quintile3
						   when _mcfp_quintile=4 then _mcfp_quintile4
						   else 0 end) quintile,
					(case when _mc_cc_orig=0 then _mc_cc_orig0
						  when _mc_cc_orig=1 then _mc_cc_orig1
						  else 0 end) cc_orig,
					(case when _mc_nas='00' then _mc_nas0
						  when _mc_nas='01' then _mc_nas1
						  when _mc_nas='02' then _mc_nas2
						  when _mc_nas='03' then _mc_nas3
						  when _mc_nas='04' then _mc_nas4    
						  when _mc_nas='05' then _mc_nas5
						  when _mc_nas='06' then _mc_nas6
						  when _mc_nas='07' then _mc_nas7
						  when _mc_nas='08' then _mc_nas8
						  when _mc_nas='09' then _mc_nas9
						  when _mc_nas='10' then _mc_nas10
						  when _mc_nas='11' then _mc_nas11
						  when _mc_nas='12' then _mc_nas12
						  else 0 end ) as nas,
					(case when _mc_cvi='0' then _mc_cvi0
						  when _mc_cvi='10' then _mc_cvi10
						  when _mc_cvi='20' then _mc_cvi20
						  when _mc_cvi='30' then _mc_cvi30
						  when _mc_cvi='40' then _mc_cvi40
						  when _mc_cvi='50' then _mc_cvi50						  
						  else 0 end) as cvi,
					( case when _mc_sdistance=1 then _mc_sdistance1
						   when _mc_sdistance=2 then _mc_sdistance2
						   when _mc_sdistance=3 then _mc_sdistance3
						   when _mc_sdistance=4 then _mc_sdistance4
						   when _mc_sdistance=5 then _mc_sdistance5
						   when _mc_sdistance=6 then _mc_sdistance6
							else 0 end) distance,	
					(case when _mc_sage_orig=1 then _mc_sage_orig1	
						  when _mc_sage_orig=2 then _mc_sage_orig2
						  when _mc_sage_orig=3 then _mc_sage_orig3	
						  when _mc_sage_orig=4 then _mc_sage_orig4	
						  else 0 end) store_age,
						  		( case when _MC_v2_z_sum=1 then _MC_z_sum1
							   when _MC_v2_z_sum=2 then _MC_z_sum2
								when _MC_v2_z_sum=3 then _MC_z_sum3
								when _MC_v2_z_sum=4 then _MC_z_sum4
								when _MC_v2_z_sum=5 then _MC_z_sum5
								when _MC_v2_z_sum=6 then _MC_z_sum6
								when _MC_v2_z_sum=7 then _MC_z_sum7
								when _MC_v2_z_sum=8 then _MC_z_sum8
								when _MC_v2_z_sum=9 then _MC_z_sum9
								when _MC_v2_z_sum=10 then _MC_z_sum10
								when _MC_v2_z_sum=11 then _MC_z_sum11
								when _MC_v2_z_sum=12 then _MC_z_sum12
								when _MC_v2_z_sum=13 then _MC_z_sum13
								when _MC_v2_z_sum=14 then _MC_z_sum14
								when _MC_v2_z_sum=15 then _MC_z_sum15
								when _MC_v2_z_sum=16 then _MC_z_sum16
								when _MC_v2_z_sum=17 then _MC_z_sum17
								else 0 end) zsum,
						
isnull(_MC_v2_07,0) * isnull(_MC_v2_070,0)  as _MC_v2_07,
isnull(_MC_v2_12,0) * isnull(_MC_v2_120,0)  as _MC_v2_12,
isnull(_MC_v2_38,0) * isnull(_MC_v2_380,0)  as _MC_v2_38,
isnull(_MC_v2_72,0) * isnull(_MC_v2_720,0)  as _MC_v2_72,
isnull(_MC_v2_73,0) * isnull(_MC_v2_730,0)  as _MC_v2_73,
isnull(_MC_v2_9K,0) * isnull(_MC_v2_9K0,0)  as _MC_v2_9K,
isnull(_MC_v2_FQ,0) * isnull(_MC_v2_FQ0,0)  as _MC_v2_FQ,
isnull(_MC_v2_IS,0) * isnull(_MC_v2_IS0,0)  as _MC_v2_IS,
isnull(_MC_v2_IT,0) * isnull(_MC_v2_IT0,0)  as _MC_v2_IT,
isnull(_MC_v2_MN,0) * isnull(_MC_v2_MN0,0)  as _MC_v2_MN,
isnull(_MC_v2_16,0) * isnull(_MC_v2_160,0)  as _MC_v2_16,
isnull(_MC_v2_74,0) * isnull(_MC_v2_740,0)  as _MC_v2_74,
isnull(_MC_v2_76,0) * isnull(_MC_v2_760,0)  as _MC_v2_76,

isnull(_MC_v2_CO,0) * isnull(_MC_v2_CO0,0)  as _MC_v2_CO,
isnull(_MC_v2_11,0) * isnull(_MC_v2_110,0)  as _MC_v2_11,
isnull(_MC_v2_34,0) * isnull(_MC_v2_340,0)  as _MC_v2_34,
isnull(_MC_v2_71,0) * isnull(_MC_v2_710,0)  as _MC_v2_71,
isnull(_MC_v2_90,0) * isnull(_MC_v2_900,0)  as _MC_v2_90,
isnull(_MC_v2_MO,0) * isnull(_MC_v2_MO0,0)  as _MC_v2_MO,
isnull(_MC_v2_NB,0) * isnull(_MC_v2_NB0,0)  as _MC_v2_NB,
isnull(_MC_v2_SD,0) * isnull(_MC_v2_SD0,0)  as _MC_v2_SD,
isnull(_MC_v2_SR,0) * isnull(_MC_v2_SR0,0)  as _MC_v2_SR,
isnull(_MC_v2_08,0) * isnull(_MC_v2_080,0)  as _MC_v2_08,
isnull(_MC_v2_30,0) * isnull(_MC_v2_300,0)  as _MC_v2_30,
isnull(_MC_v2_40,0) * isnull(_MC_v2_400,0)  as _MC_v2_40,
isnull(_MC_v2_64,0) * isnull(_MC_v2_640,0)  as _MC_v2_64,
isnull(_MC_v2_66,0) * isnull(_MC_v2_660,0)  as _MC_v2_66,
isnull(_MC_v2_CA,0) * isnull(_MC_v2_CA0,0)  as _MC_v2_CA,
isnull(_MC_v2_NF,0) * isnull(_MC_v2_NF0,0)  as _MC_v2_NF,
isnull(_MC_v2_RS,0) * isnull(_MC_v2_RS0,0)  as _MC_v2_RS,
isnull(_MC_v2_WL,0) * isnull(_MC_v2_WL0,0)  as _MC_v2_WL,
isnull(_MC_v2_10,0) * isnull(_MC_v2_100,0)  as _MC_v2_10,
isnull(_MC_v2_15,0) * isnull(_MC_v2_150,0)  as _MC_v2_15,
isnull(_MC_v2_28,0) * isnull(_MC_v2_280,0)  as _MC_v2_28,
isnull(_MC_v2_44,0) * isnull(_MC_v2_440,0)  as _MC_v2_44,
isnull(_MC_v2_49,0) * isnull(_MC_v2_490,0)  as _MC_v2_49,
isnull(_MC_v2_51,0) * isnull(_MC_v2_510,0)  as _MC_v2_51,
isnull(_MC_v2_75,0) * isnull(_MC_v2_750,0)  as _MC_v2_75,

isnull(_MC_v2_9D,0) * isnull(_MC_v2_9D0,0)  as _MC_v2_9D,
isnull(_MC_v2_BO,0) * isnull(_MC_v2_BO0,0)  as _MC_v2_BO,
isnull(_MC_v2_CL,0) * isnull(_MC_v2_CL0,0)  as _MC_v2_CL,
isnull(_MC_v2_CZ,0) * isnull(_MC_v2_CZ0,0)  as _MC_v2_CZ,
isnull(_MC_v2_DI,0) * isnull(_MC_v2_DI0,0)  as _MC_v2_DI,
isnull(_MC_v2_MI,0) * isnull(_MC_v2_MI0,0)  as _MC_v2_MI,
isnull(_MC_v2_02,0) * isnull(_MC_v2_020,0)  as _MC_v2_02,
isnull(_MC_v2_03,0) * isnull(_MC_v2_030,0)  as _MC_v2_03,
isnull(_MC_v2_26,0) * isnull(_MC_v2_260,0)  as _MC_v2_26,
isnull(_MC_v2_29,0) * isnull(_MC_v2_290,0)  as _MC_v2_29,
isnull(_MC_v2_37,0) * isnull(_MC_v2_370,0)  as _MC_v2_37,
isnull(_MC_v2_48,0) * isnull(_MC_v2_480,0)  as _MC_v2_48,
isnull(_MC_v2_52,0) * isnull(_MC_v2_520,0)  as _MC_v2_52,
isnull(_MC_v2_82,0) * isnull(_MC_v2_820,0)  as _MC_v2_82,
isnull(_MC_v2_FV,0) * isnull(_MC_v2_FV0,0)  as _MC_v2_FV,
isnull(_MC_v2_04,0) * isnull(_MC_v2_040,0)  as _MC_v2_04,
isnull(_MC_v2_06,0) * isnull(_MC_v2_060,0)  as _MC_v2_06,
isnull(_MC_v2_09,0) * isnull(_MC_v2_090,0)  as _MC_v2_09,
isnull(_MC_v2_14,0) * isnull(_MC_v2_140,0)  as _MC_v2_14,
isnull(_MC_v2_19,0) * isnull(_MC_v2_190,0)  as _MC_v2_19,
isnull(_MC_v2_25,0) * isnull(_MC_v2_250,0)  as _MC_v2_25,
isnull(_MC_v2_89,0) * isnull(_MC_v2_890,0)  as _MC_v2_89,
isnull(_MC_v2_PA,0) * isnull(_MC_v2_PA0,0)  as _MC_v2_PA,
isnull(_MC_v2_27,0) * isnull(_MC_v2_270,0)  as _MC_v2_27,
isnull(_MC_v2_31,0) * isnull(_MC_v2_310,0)  as _MC_v2_31,
isnull(_MC_v2_50,0) * isnull(_MC_v2_500,0)  as _MC_v2_50,
isnull(_MC_v2_80,0) * isnull(_MC_v2_800,0)  as _MC_v2_80,
isnull(_MC_v2_85,0) * isnull(_MC_v2_850,0)  as _MC_v2_85,
isnull(_MC_v2_MS,0) * isnull(_MC_v2_MS0,0)  as _MC_v2_MS,
isnull(_MC_v2_PO,0) * isnull(_MC_v2_PO0,0)  as _MC_v2_PO,
isnull(_MC_v2_VA,0) * isnull(_MC_v2_VA0,0)  as _MC_v2_VA,
isnull(_MC_v2_ZI,0) * isnull(_MC_v2_ZI0,0)  as _MC_v2_ZI,
						  
				


					 
			
					isnull(_m_age_1 * _m_age,0) cus_age, 
					--isnull(_m_monthlyincome_1 * _m_monthlyincome,0)+
					isnull(_m_ltc_1 * _m_ltc,0) ltc

				from #noncore_pre_scoring


