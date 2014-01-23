$(document).ready(function($) {

  var backup_delay_auth_decision = undefined;

  $('#middlewares_staticweb_enabled, #middlewares_tempurl_enabled, #middlewares_formpost_enabled').on('change', function() {
    var value = $(this).val();

    if (value == 'true') {
      if (backup_delay_auth_decision == undefined) {
        backup_delay_auth_decision = $('#keystone_delay_auth_decision').val();
      }
      $('#keystone_delay_auth_decision').val('true').attr('disabled', 'disabled');
    }
    else if ($('#middlewares_staticweb_enabled').val() == 'false' &&
             $('#middlewares_tempurl_enabled').val() == 'false' &&
             $('#middlewares_formpost_enabled').val() == 'false')
    {
      $('#keystone_delay_auth_decision').removeAttr('disabled');
      if (backup_delay_auth_decision != undefined) {
        $('#keystone_delay_auth_decision').val(backup_delay_auth_decision);
        backup_delay_auth_decision = undefined;
      }
    }
  }).trigger('change');
}); 

