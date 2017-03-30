----------------------------------------------------------------------
/* create base set with leases having a buyout after '2016-01-01'*/
---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#buyout_dubles') is not null
drop table #buyout_dubles
	select 
		approvalbkey, 
		sum(buyoutpayment) sum_buyout
		INTO #buyout_dubles
		FROM datawarehouse..fact_journalentry 
			where buyoutpayment=1 and entity='client'
		group by approvalbkey having sum(buyoutpayment)>0  and min(effectivedate)>'2016-01-01'
------------------------------------------------------------------------------------
/* create relavent buyout dates and aggregate information to approvalbkey level*/
------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#buyout_paynumbers') is not null
drop table #buyout_paynumbers
	select
		 approvalbkey   
		,settled_buyouts = sum(case when acctdesc='Payment - Settled' then 1 else 0 end)
		/* grace period*/
		, elligible_buyouts=sum(case when effectivedate<= convert(date,getdate()-7) and buyoutpayment=1 and acctdesc <>'Payment - Cancelled' then 1 else 0 end)
		,sum(buyoutpayment) total_buyouts_scheduled
		, active_cancelled_buyouts= sum(case when buyoutpayment=1 and acctdesc ='Payment - Cancelled' and EffectiveDate<=convert(date,getdate()-7) then 1 else 0 end),
		future_cancelled_buyouts=sum(case when buyoutpayment=1 and acctdesc ='Payment - Cancelled' and EffectiveDate>convert(date,getdate()-7) then 1 else 0 end)
		,missed_buyouts=sum(case when effectivedate<= convert(date,getdate()-7) and buyoutpayment=1 and acctdesc = 'Payment - Returned' then 1 else 0 end),
		First_buyout_scheduled=min(case when  buyoutpayment=1 then effectivedate else null end),
		active_pending_buyouts=sum(case when buyoutpayment=1 and acctdesc = 'Payment - Pending' and EffectiveDate<=convert(date,getdate()-7)then 1 else 0 end ),
		future_pending_buyouts=sum(case when buyoutpayment=1 and acctdesc = 'Payment - Pending' and EffectiveDate>convert(date,getdate()-7)then 1 else 0 end ),
		last_buyout_scheduled=max(case when  buyoutpayment=1 then effectivedate else null end),
		Most_recent_elligible=max(case when effectivedate<= convert(date,getdate()-7) and buyoutpayment=1 then effectivedate else null end),
		most_recent_success=max( case when buyoutpayment=1 and acctdesc='Payment - Settled' then effectivedate else null end)
		
	INTO #buyout_paynumbers
	FROM datawarehouse..fact_journalentry where   entity='client' and effectivedate>='2016-01-01' and buyoutpayment=1 and approvalbkey in ( select approvalbkey from #buyout_dubles)
	
	group by approvalbkey

---------------------------
/* create buyout_type*/
---------------------------
IF OBJECT_ID('tempdb..#buyout_paynumbers2') is not null
DROP TABLE #buyout_paynumbers2
	select 
		*, 
        Buyout_type=case 
		                 when elligible_buyouts>0 and elligible_buyouts=settled_buyouts then 'All Eligible paid'
						 when elligible_buyouts> settled_buyouts then 'At least 1 Buyout Missed'
						 when settled_buyouts=0 then 'No Buyouts Paid'
						 else 'undetermined'end
						/*,
		Multiple_buyout= case when total_buyouts_scheduled =1 then 'Single Buyout' 
		                      when total_buyouts_scheduled =2 then 'Double Buyout'
							  when total_buyouts_scheduled =3 then 'Triple Buyout'
							  when total_buyouts_scheduled =4 then 'Quartic Buyout'
							  when total_buyouts_scheduled =5 then 'Quintuple Buyout'
							  else 'Greater than Five Buyouts scheduled'
							  end*/
	INTO #buyout_paynumbers2
	FROM #buyout_paynumbers
	where (Most_recent_elligible<= convert(date,getdate()-7) )
	       

	-----------------------------------------------------------------------------------------
	/* add wnli_leaseview attributes, whether was blitzed , DQ and add calculated variables*/
	-----------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FINAL_LIST') is not null
DROP TABLE #FINAL_LIST
	select 
		   lv.approvalid,
		   lv.leasestatus,
	       a.*,		  
		   convert(date,lv.leaseaddeddate) leaseaddeddate,
		   lv.leaseamount,
			dq.TotalPaid,
			 ROI=dq.TotalPaid/lv.leaseamount,	   
		   dq.balance balance_owed,
		   dq.dpddate,
		   daysinbuyout=datediff(day,a.First_buyout_scheduled,convert(date,getdate())),
		   dqdays=isnull(datediff(day,dq.dpddate,convert(date,getdate())),0),
		   blitzed=isnull(nullif(isnull(cb.approvalid,0),cb.approvalid),1),
		   added_to_list_date = convert(date,getdate())
		 INTO  #FINAL_LIST
		 FROM #buyout_paynumbers2 a
			left join datawarehouse..dim_approval app
				on a.approvalbkey=app.approvalbkey
			left join rto..wnli_leaseview lv
				on	app.approvalid=lv.approvalid
			left join datawarehouse..dqjournal dq
				on a.approvalbkey=dq.approvalbkey
			left join rto..wnli_cardblitzprocess2 cb
				on cb.approvalid = lv.approvalid and convert(date,cb.ts)=convert(date,getdate())
			where 
			 dq.balance >100
			 and (convert(date,getdate()) >= currentDate 
			 and convert(date,getdate())<nextdate) 
			 and dq.currentleasestatus<>'CHARGEOFF'
			 and datediff(day,dq.dpddate,convert(date,getdate()))>7
			 and missed_buyouts>0
			 and isnull(most_recent_success,convert(date,'1990-01-01'))<=  convert(date,getdate()-7)


--------------
--dupcheck
-------------
select * from  #FINAL_LIST where approvalid in (select approvalid from #final_list group by approvalid having count(approvalid)>1)

 --create start table 
drop table  analytics..buyout_collection_list
select * 
into analytics..buyout_collection_list
from #FINAL_LIST
------------------------------------------
/* add new leases to list */
-----------------------------------------

----just grab new list 
insert into analytics..buyout_collection_list
select 
	*
	from #final_list where approvalbkey not in ( select approvalbkey from analytics..buyout_collection_list)



	select * from analytics..buyout_collection_list 
/* select final list */

select  approvalid,leasestatus, missed_buyouts,ROI, balance_owed,dqdays,daysinbuyout from analytics..buyout_collection_list -- where added_to_list_date=convert(date,getdate())
where (dqdays<= 60 and roi<=2) or (dqdays>60 and ROI<=1.5)
order by dqdays, missed_buyouts desc, balance_owed 

--Cleanup
Drop table #FINAL_LIST
Drop table #buyout_paynumbers2
Drop table #buyout_paynumbers
Drop table #buyout_dubles



---list recreation 
select  * from #FINAL_LIST -- where added_to_list_date=convert(date,getdate())
where (dqdays<= 60 and roi<=2) or (dqdays>60 and ROI<=1.5)
order by added_to_list_date desc, missed_buyouts desc, balance_owed 


select   * from 
datawarehouse..BuyoutCollectionList
order by dqdays 

