$(document).ready(function($) {

  $('#middlewares_staticweb_enabled, #middlewares_tempurl_enabled, #middlewares_formpost_enabled').on('change', function() {
    var value = $(this).val();

    var delay_auth_decision = $('#keystone_delay_auth_decision')
    var backup_delay_auth_decision = delay_auth_decision.data('backup');

    if (value == 'true') {
      if (backup_delay_auth_decision == undefined) {
        delay_auth_decision.data('backup', delay_auth_decision.val());
      }
      delay_auth_decision.val('true').attr('disabled', 'disabled').trigger('change');
    }
    else if ($('#middlewares_staticweb_enabled').val() == 'false' &&
             $('#middlewares_tempurl_enabled').val() == 'false' &&
             $('#middlewares_formpost_enabled').val() == 'false')
    {
      delay_auth_decision.removeAttr('disabled');
      if (backup_delay_auth_decision != undefined) {
        delay_auth_decision.val(backup_delay_auth_decision).trigger('change');
        delay_auth_decision.removeData('backup');
      }
    }
  }).trigger('change');
}); 

