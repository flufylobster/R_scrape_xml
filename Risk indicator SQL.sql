


--- grab and dedeup risk indicator by approval id 
if object_id('tempdb..#ln_rsk') is not null
	drop table #ln_rsk

select approvalid, riskcode,sequence 

into #ln_rsk
from 

(select 
	lv.approvalid, 
	Riskcode=isnull(ri.riskcode,'NONE'),
	sequence=row_number() over ( partition by lv.approvalid, isnull(ri.riskcode,'NONE') order by  lv.approvalid, isnull(ri.riskcode,'NONE'))

 from rto..wnli_leaseview lv
       
		left join intelreports..fp_applicant a
			on a.approvalid=lv.approvalid
		left join intelreports..fp_riskindicators ri
			on a.applicantid=ri.applicantid
		where a.applicantid>=1
) a where a.sequence=1		


-- check dedup use on subquery
		--select count(*)  from #ln_rsk where sequence =1 

-- identical to 
           --select count(*) from #ln_rsk group by approvalid,riskcode

DECLARE @pivcol AS NVARCHAR(MAX),
    @query  AS NVARCHAR(MAX),	
	@colname as nvarchar(max);
SET @pivcol = STUFF((SELECT distinct ',' + QUOTENAME('_MC_v2_' + c.riskcode) 
            FROM #ln_rsk c
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)') 
        ,1,1,'')


SET @colname = STUFF((SELECT distinct ', isnull('+ QUOTENAME('_MC_v2_' + c.riskcode) +',0) as' +quotename('_MC_v2_' + c.riskcode)
            FROM #ln_rsk c
            FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)') 
        ,1,1,'')

set @query = 'drop table ##risk_indicators SELECT approvalid, '    +@colname  +   ' 
			into ##risk_indicators
			from 
            (
                select approvalid
                    , ''_MC_v2_'' + riskcode as riskcode, sequence
                    
                from #ln_rsk
           ) x
            pivot 
            (
                 max(sequence)
				
                for riskcode in ('  +@pivcol  +  ')
            ) p  order by approvalid'

-- create table ##risk_indicators
execute(@query)


-- add sum 

if object_id('tempdb..#riskindicators ') is not null
	drop table #riskindicators 

select a.*, b.sequence as _mc_v2_z_sum  

into #riskindicators 
from ##risk_indicators a 
		  left join ( select approvalid, sum(sequence) as sequence from #ln_rsk group by approvalid) b
		  on a.approvalid=b.ApprovalID
			





