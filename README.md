# mikrotik-sms-forwarder

Forwards incoming SMS from a MikroTik RouterOS LTE device to a Matrix room, so messages arriving on a remote SIM can be read from anywhere.

It runs as a RouterOS script on a schedule: reads the modem inbox, decodes the text (including UCS-2 / Cyrillic), and delivers it. An SMS is removed only after a successful delivery, so a failed send is retried instead of lost.

Status: work in progress.
