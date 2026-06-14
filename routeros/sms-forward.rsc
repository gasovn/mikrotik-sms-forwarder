/system script run sms-config
:global matrixEnabled
:global mxHs
:global mxRoom
:global mxToken
:global telegramEnabled
:global tgWorkerUrl
:global tgSecret

:global smsForwardSeq
:if ([:typeof $smsForwardSeq] != "num") do={ :set smsForwardSeq 0 }

:local hexv "0123456789ABCDEF"

:local gtotal ({})
:local gparts ({})
:local gids ({})
:local gphone ({})
:local gts ({})
:local gdcs ({})

:foreach m in=[/tool sms inbox find] do={
  :local pdu [/tool sms inbox get $m pdu]
  :local phone [/tool sms inbox get $m phone]
  :local ts [/tool sms inbox get $m timestamp]
  :local msg [/tool sms inbox get $m message]
  :local p 0
  :local smscLen (([:find $hexv [:pick $pdu 0 1]]*16)+[:find $hexv [:pick $pdu 1 2]])
  :set p (2 + $smscLen*2)
  :local ptype (([:find $hexv [:pick $pdu $p ($p+1)]]*16)+[:find $hexv [:pick $pdu ($p+1) ($p+2)]])
  :local udhi (($ptype & 64) = 64)
  :set p ($p+2)
  :local alen (([:find $hexv [:pick $pdu $p ($p+1)]]*16)+[:find $hexv [:pick $pdu ($p+1) ($p+2)]])
  :set p ($p + 4 + ((($alen+1)/2)*2))
  :set p ($p+2)
  :local dcs (([:find $hexv [:pick $pdu $p ($p+1)]]*16)+[:find $hexv [:pick $pdu ($p+1) ($p+2)]])
  :set p ($p+2+14)
  :local udl (([:find $hexv [:pick $pdu $p ($p+1)]]*16)+[:find $hexv [:pick $pdu ($p+1) ($p+2)]])
  :set p ($p+2)
  :local udEnd ($p + $udl*2)
  :local ref 0
  :local total 1
  :local part 1
  :local concat false
  :if ($udhi) do={
    :local udhl (([:find $hexv [:pick $pdu $p ($p+1)]]*16)+[:find $hexv [:pick $pdu ($p+1) ($p+2)]])
    :local iei (([:find $hexv [:pick $pdu ($p+2) ($p+3)]]*16)+[:find $hexv [:pick $pdu ($p+3) ($p+4)]])
    :if ($iei = 0) do={
      :set ref (([:find $hexv [:pick $pdu ($p+6) ($p+7)]]*16)+[:find $hexv [:pick $pdu ($p+7) ($p+8)]])
      :set total (([:find $hexv [:pick $pdu ($p+8) ($p+9)]]*16)+[:find $hexv [:pick $pdu ($p+9) ($p+10)]])
      :set part (([:find $hexv [:pick $pdu ($p+10) ($p+11)]]*16)+[:find $hexv [:pick $pdu ($p+11) ($p+12)]])
      :set concat true
    }
    :if ($iei = 8) do={
      :set ref (((([:find $hexv [:pick $pdu ($p+6) ($p+7)]]*16)+[:find $hexv [:pick $pdu ($p+7) ($p+8)]])*256)+(([:find $hexv [:pick $pdu ($p+8) ($p+9)]]*16)+[:find $hexv [:pick $pdu ($p+9) ($p+10)]]))
      :set total (([:find $hexv [:pick $pdu ($p+10) ($p+11)]]*16)+[:find $hexv [:pick $pdu ($p+11) ($p+12)]])
      :set part (([:find $hexv [:pick $pdu ($p+12) ($p+13)]]*16)+[:find $hexv [:pick $pdu ($p+13) ($p+14)]])
      :set concat true
    }
    :set p ($p+2+$udhl*2)
  }
  :local rep ""
  :if ($dcs = 8) do={ :set rep [:pick $pdu $p $udEnd] } else={ :set rep $msg }
  :local gk ("s" . $m)
  :if ($concat) do={ :set gk ($phone . "#" . $ref) }
  :set ($gtotal->$gk) $total
  :set ($gparts->($gk . "#" . $part)) $rep
  :set ($gphone->$gk) $phone
  :set ($gts->$gk) $ts
  :set ($gdcs->$gk) $dcs
  :local cur ($gids->$gk)
  :if ([:typeof $cur] = "nothing") do={ :set cur "" }
  :set ($gids->$gk) ($cur . "," . $m)
}

:foreach gk,tot in=$gtotal do={
  :local complete true
  :local agg ""
  :for i from=1 to=$tot do={
    :local pv ($gparts->($gk . "#" . $i))
    :if ([:typeof $pv] = "nothing") do={ :set complete false } else={ :set agg ($agg . $pv) }
  }
  :if ($complete) do={
    :local phone ($gphone->$gk)
    :local ts ($gts->$gk)
    :local dcs ($gdcs->$gk)
    :local prefix ("[" . [:pick $ts 0 10] . " " . [:pick $ts 11 16] . "] " . $phone . ": ")
    :local chunks ({})
    :local nchunks 0
    :if ($dcs = 8) do={
      :local La [:len $agg]
      :local pos 0
      :while ($pos < $La) do={
        :local seg [:pick $agg $pos ($pos+400)]
        :local txt ""
        :local k 0
        :local Ls [:len $seg]
        :while ($k < $Ls) do={ :set txt ($txt . "\\u" . [:pick $seg $k ($k+4)]) ; :set k ($k+4) }
        :set ($chunks->$nchunks) $txt
        :set nchunks ($nchunks+1)
        :set pos ($pos+400)
      }
    } else={
      :local La [:len $agg]
      :local pos 0
      :while ($pos < $La) do={
        :local seg [:pick $agg $pos ($pos+100)]
        :local txt ""
        :local k 0
        :local Ls [:len $seg]
        :while ($k < $Ls) do={
          :local ch [:pick $seg $k ($k+1)]
          :local esc $ch
          :if ($ch = "\"") do={ :set esc "\\\"" }
          :if ($ch = "\\") do={ :set esc "\\\\" }
          :if ($ch = "\n") do={ :set esc "\\n" }
          :if ($ch = "\r") do={ :set esc "\\r" }
          :if ($ch = "\t") do={ :set esc "\\t" }
          :set txt ($txt . $esc)
          :set k ($k+1)
        }
        :set ($chunks->$nchunks) $txt
        :set nchunks ($nchunks+1)
        :set pos ($pos+100)
      }
    }
    :local allOk true
    :local ci 0
    :while ($ci < $nchunks) do={
      :local inner $prefix
      :if ($ci > 0) do={ :set inner "" }
      :set inner ($inner . ($chunks->$ci))
      :local txn ("m" . $smsForwardSeq)
      :set smsForwardSeq ($smsForwardSeq + 1)
      :local okc false
      :if ($matrixEnabled) do={
        :local rid $mxRoom
        :local cp [:find $rid ":"]
        :local enc ("%21" . [:pick $rid 1 $cp] . "%3A" . [:pick $rid ($cp+1) [:len $rid]])
        :local url ("https://" . $mxHs . "/_matrix/client/v3/rooms/" . $enc . "/send/m.room.message/" . $txn)
        :local body ("{\"msgtype\":\"m.text\",\"body\":\"" . $inner . "\"}")
        :do {
          /tool fetch http-method=put url=$url http-header-field=("Authorization: Bearer " . $mxToken . ",Content-Type: application/json") http-data=$body mode=https keep-result=no
          :set okc true
        } on-error={}
      }
      :if ($telegramEnabled) do={
        :local body ("{\"text\":\"" . $inner . "\"}")
        :do {
          /tool fetch http-method=post url=$tgWorkerUrl http-header-field=("X-Auth: " . $tgSecret . ",Content-Type: application/json") http-data=$body mode=https keep-result=no
          :set okc true
        } on-error={}
      }
      :if (!$okc) do={ :set allOk false }
      :set ci ($ci+1)
    }
    :if ($allOk) do={
      :if ($nchunks > 0) do={
        :foreach id in=[:toarray [:pick ($gids->$gk) 1 [:len ($gids->$gk)]]] do={ :do { /tool sms inbox remove $id } on-error={} }
      }
    }
  }
}
