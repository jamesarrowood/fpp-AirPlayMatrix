<div style="margin:0 auto;">
  <br />
  <fieldset style="padding: 10px; border: 2px solid #000;">
    <legend>AirPlay Video Matrix Plugin</legend>
    <div style="overflow: hidden; padding: 10px;">
      <b>Purpose:</b><br />
      Receive AirPlay video mirroring and display the video on an FPP matrix overlay model.<br /><br />

      <b>Runtime Stack:</b><br />
      - UxPlay (AirPlay receiver)<br />
      - GStreamer bridge to RGB frames<br />
      - FPP overlay shared memory writer<br /><br />

      <b>Notes:</b><br />
      This plugin scales the incoming AirPlay frame to your matrix dimensions.
    </div>
  </fieldset>
</div>
